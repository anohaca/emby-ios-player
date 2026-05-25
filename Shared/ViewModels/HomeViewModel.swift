//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Defaults
import Factory
import Foundation
import IdentifiedCollections
import Nuke
import OrderedCollections

@MainActor
final class HomeViewModel: ViewModel, Stateful {

    // MARK: Action

    enum Action: Equatable {
        case applyUserDataOverrides
        case backgroundRefresh
        case error(ErrorMessage)
        case refreshIfPendingInvalidation
        case setIsPlayed(Bool, BaseItemDto)
        case setRefreshSuspended(Bool)
        case refresh
    }

    // MARK: BackgroundState

    enum BackgroundState: Hashable {
        case refresh
    }

    // MARK: State

    enum State: Hashable {
        case content
        case error(ErrorMessage)
        case initial
        case refreshing
    }

    @Published
    private(set) var libraries: [LatestInLibraryViewModel] = []
    @Published
    var resumeItems: OrderedSet<BaseItemDto> = []

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var state: State = .initial

    // TODO: replace with views checking what notifications were
    //       posted since last disappear
    @Published
    var notificationsReceived: NotificationSet = .init()

    private var backgroundRefreshTask: AnyCancellable?
    private var notificationRefreshTask: AnyCancellable?
    private var refreshTask: AnyCancellable?
    private var resumeImagePreheatTask: Task<Void, Never>?
    private var isRefreshSuspended = false
    private var didHoldSuspendedRefreshNotification = false
    private static let resumeItemLimit = 20

    var nextUpViewModel: NextUpLibraryViewModel = .init()
    var recentlyAddedViewModel: RecentlyAddedLibraryViewModel = .init()

    override init() {
        super.init()

        Task { @MainActor [weak self] in
            self?.applyCachedHomeStateIfAvailable()
        }

        Notifications[.itemMetadataDidChange]
            .publisher
            .sink { [weak self] _ in
                // Necessary because when this notification is posted, even with asyncAfter,
                // the view will cause layout issues since it will redraw while in landscape.
                // TODO: look for better solution
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.notificationsReceived.insert(.itemMetadataDidChange)
                    self.markPendingHomeRefresh()
                    self.applyUserDataOverridesToVisibleItems()
                    self.scheduleNotificationDrivenRefresh()
                }
            }
            .store(in: &cancellables)

        Notifications[.itemShouldRefreshMetadata]
            .publisher
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.notificationsReceived.insert(.itemShouldRefreshMetadata)
                    self.markPendingHomeRefresh()
                    self.applyUserDataOverridesToVisibleItems()
                    self.scheduleNotificationDrivenRefresh()
                }
            }
            .store(in: &cancellables)

        Notifications[.resumeItemRecencyDidChange]
            .publisher
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.notificationsReceived.insert(.resumeItemRecencyDidChange)
                    self.markPendingHomeRefresh()
                    self.reorderResumeItemsFromLocalRecency()
                    self.applyUserDataOverridesToVisibleItems()

                    self.scheduleNotificationDrivenRefresh()
                }
            }
            .store(in: &cancellables)

        Notifications[.willPresentVideoPlayer]
            .publisher
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.send(.setRefreshSuspended(true))
                }
            }
            .store(in: &cancellables)
    }

    func respond(to action: Action) -> State {
        switch action {
        case .applyUserDataOverrides:
            applyUserDataOverridesToVisibleItems()
            if state == .content {
                cacheCurrentHomeState()
            }
            return state
        case .backgroundRefresh:
            guard !isRefreshSuspended else {
                markPendingHomeRefresh()
                #if DEBUG
                NSLog("EmbyHomeExitTrace backgroundRefresh-skipped reason=suspended")
                #endif
                return state
            }

            backgroundRefreshTask?.cancel()
            backgroundStates.insert(.refresh)

            backgroundRefreshTask = Task { [weak self] in
                do {
                    try await self?.refresh()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.backgroundStates.remove(.refresh)
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                        self.logger.error("Home background refresh failed: \(error.embyDiagnosticDescription)")
                        if self.state != .content {
                            self.send(.error(.init(error.embyDisplayDescription)))
                        }
                    }
                }
            }
            .asAnyCancellable()

            return state
        case let .error(error):
            return .error(error)
        case .refreshIfPendingInvalidation:
            applyUserDataOverridesToVisibleItems()

            guard hasPendingHomeRefresh() else { return state }
            guard !isRefreshSuspended else {
                #if DEBUG
                NSLog("EmbyHomeExitTrace pending-refresh-held reason=suspended")
                #endif
                return state
            }

            if state == .content {
                self.send(.backgroundRefresh)
            } else {
                self.send(.refresh)
            }

            return state
        case let .setIsPlayed(isPlayed, item): ()
            Task {
                try await setIsPlayed(isPlayed, for: item)

                self.send(.backgroundRefresh)
            }
            .store(in: &cancellables)

            return state
        case let .setRefreshSuspended(isSuspended):
            isRefreshSuspended = isSuspended
            didHoldSuspendedRefreshNotification = false
            #if DEBUG
            NSLog("EmbyHomeExitTrace refresh-suspended=%@", isSuspended.description)
            #endif

            if isSuspended {
                if backgroundStates.contains(.refresh) || refreshTask != nil || backgroundRefreshTask != nil {
                    markPendingHomeRefresh()
                }
                backgroundRefreshTask?.cancel()
                notificationRefreshTask?.cancel()
                refreshTask?.cancel()
                backgroundStates.remove(.refresh)
            }

            return state
        case .refresh:
            guard !isRefreshSuspended else {
                markPendingHomeRefresh()
                #if DEBUG
                NSLog("EmbyHomeExitTrace refresh-skipped reason=suspended")
                #endif
                return state == .content ? state : .refreshing
            }

            backgroundRefreshTask?.cancel()
            refreshTask?.cancel()

            if state != .content {
                applyCachedHomeStateIfAvailable()
            }

            let nextState = state == .content ? state : State.refreshing
            if state == .content {
                backgroundStates.insert(.refresh)
            }

            refreshTask = Task { [weak self] in
                do {
                    try await self?.refresh()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                        self.state = .content
                    }
                } catch is CancellationError {
                    // cancelled
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                        self.logger.error("Home refresh failed: \(error.embyDiagnosticDescription)")
                        if self.state != .content {
                            self.send(.error(.init(error.embyDisplayDescription)))
                        }
                    }
                }
            }
            .asAnyCancellable()

            return nextState
        }
    }

    private func refresh() async throws {
        #if DEBUG
        let refreshStart = CACurrentMediaTime()
        NSLog(
            "EmbyHomeExitTrace refresh-begin state=%@ background=%@ resume=%d libraries=%d",
            String(describing: state),
            backgroundStates.contains(.refresh).description,
            resumeItems.count,
            libraries.count
        )
        #endif

        try await refreshLibrary(nextUpViewModel)
        try Task.checkCancellation()
        #if DEBUG
        NSLog("EmbyHomeExitTrace refresh-step nextUp elapsed=%.3f count=%d", CACurrentMediaTime() - refreshStart, nextUpViewModel.elements.count)
        #endif
        try await refreshLibrary(recentlyAddedViewModel)
        try Task.checkCancellation()
        #if DEBUG
        NSLog("EmbyHomeExitTrace refresh-step recentlyAdded elapsed=%.3f count=%d", CACurrentMediaTime() - refreshStart, recentlyAddedViewModel.elements.count)
        #endif

        let libraries = try await getLibraries()
        try Task.checkCancellation()
        #if DEBUG
        NSLog("EmbyHomeExitTrace refresh-step libraries elapsed=%.3f count=%d", CACurrentMediaTime() - refreshStart, libraries.count)
        #endif
        let resumeItems = try await getResumeItems(for: libraries)
        try Task.checkCancellation()
        #if DEBUG
        NSLog("EmbyHomeExitTrace refresh-step resume elapsed=%.3f count=%d", CACurrentMediaTime() - refreshStart, resumeItems.count)
        #endif

        for (index, library) in libraries.enumerated() {
            try await refreshLibrary(library)
            try Task.checkCancellation()
            #if DEBUG
            NSLog(
                "EmbyHomeExitTrace refresh-step library[%d] elapsed=%.3f title=%@ count=%d",
                index,
                CACurrentMediaTime() - refreshStart,
                library.parent?.displayTitle ?? "<nil>",
                library.elements.count
            )
            #endif
        }

        await MainActor.run {
            #if DEBUG
            let applyStart = CACurrentMediaTime()
            #endif
            self.resumeItems.elements = resumeItems
            self.libraries = libraries
            self.applyUserDataOverridesToVisibleItems()
            self.cacheCurrentHomeState()
            self.preheatResumeItemImages()
            _ = self.consumePendingHomeRefresh()
            #if DEBUG
            NSLog(
                "EmbyHomeExitTrace refresh-apply elapsed=%.3f apply=%.3f resume=%d libraries=%d",
                CACurrentMediaTime() - refreshStart,
                CACurrentMediaTime() - applyStart,
                self.resumeItems.count,
                self.libraries.count
            )
            #endif
        }
    }

    private func refreshLibrary(_ viewModel: PagingLibraryViewModel<BaseItemDto>) async throws {
        #if DEBUG
        let start = CACurrentMediaTime()
        let title = viewModel.parent?.displayTitle ?? String(describing: type(of: viewModel))
        #endif
        try await viewModel.refresh()
        viewModel.state = .content
        #if DEBUG
        NSLog(
            "EmbyHomeExitTrace refresh-library title=%@ elapsed=%.3f count=%d",
            title,
            CACurrentMediaTime() - start,
            viewModel.elements.count
        )
        #endif
    }

    private func markPendingHomeRefresh() {
        guard let userSession else { return }
        HomeRefreshInvalidationStore.mark(
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func consumePendingHomeRefresh() -> Bool {
        guard let userSession else { return false }
        return HomeRefreshInvalidationStore.consume(
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func hasPendingHomeRefresh() -> Bool {
        guard let userSession else { return false }
        return HomeRefreshInvalidationStore.hasPending(
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func scheduleNotificationDrivenRefresh() {
        notificationRefreshTask?.cancel()
        guard !isRefreshSuspended else {
            #if DEBUG
            if !didHoldSuspendedRefreshNotification {
                NSLog("EmbyHomeExitTrace notification-refresh held reason=suspended pending=%@", hasPendingHomeRefresh().description)
            }
            #endif
            didHoldSuspendedRefreshNotification = true
            return
        }
        #if DEBUG
        NSLog("EmbyHomeExitTrace notification-refresh scheduled pending=%@", hasPendingHomeRefresh().description)
        #endif

        notificationRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }

            await MainActor.run {
                guard let self, self.state == .content, self.hasPendingHomeRefresh() else { return }
                #if DEBUG
                NSLog("EmbyHomeExitTrace notification-refresh fire")
                #endif
                self.send(.backgroundRefresh)
            }
        }
        .asAnyCancellable()
    }

    private func getResumeItems(for libraries: [LatestInLibraryViewModel]) async throws -> [BaseItemDto] {
        let libraryIDs = Self.libraryIDs(from: libraries)
        let hiddenLibraryIDs = Self.hiddenHomeLibraryIDs().intersection(libraryIDs)

        guard hiddenLibraryIDs.isNotEmpty else {
            return sortedResumeItems(try await getResumeItems(parentID: nil))
        }

        let visibleLibraryIDs = libraryIDs.filter { !hiddenLibraryIDs.contains($0) }
        guard visibleLibraryIDs.isNotEmpty else { return [] }

        var items: [BaseItemDto] = []
        for libraryID in visibleLibraryIDs {
            items.append(contentsOf: try await getResumeItems(parentID: libraryID))
        }

        return sortedResumeItems(Self.uniqueItems(items))
    }

    private func getResumeItems(parentID: String?) async throws -> [BaseItemDto] {
        var parameters = EmbyPortResumeItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields + [.primaryImageAspectRatio]
        parameters.limit = Self.resumeItemLimit
        parameters.mediaTypes = [.video]
        parameters.parentID = parentID
        parameters.sortBy = [.datePlayed]
        parameters.sortOrder = [.descending]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.resumeItems(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items ?? []
    }

    private func sortedResumeItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
        return ResumeItemRecencyStore.sorted(
            items,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
        .prefix(Self.resumeItemLimit)
        .asArray
    }

    private func reorderResumeItemsFromLocalRecency() {
        resumeItems.elements = ResumeItemRecencyStore.sorted(
            resumeItems.elements,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func applyUserDataOverridesToVisibleItems() {
        guard let userSession else { return }

        let serverID = userSession.server.id
        let userID = userSession.user.id

        let recentlyAddedItems = HomeItemUserDataOverrideStore.applyingOverrides(
            to: Array(recentlyAddedViewModel.elements),
            serverID: serverID,
            userID: userID
        )
        let libraryItems = libraries.map { library in
            (
                library,
                HomeItemUserDataOverrideStore.applyingOverrides(
                    to: Array(library.elements),
                    serverID: serverID,
                    userID: userID
                )
            )
        }
        let visiblePlayedItemIDs = HomeItemUserDataOverrideStore.playedItemIDs(
            in: recentlyAddedItems + libraryItems.flatMap { $0.1 },
            serverID: serverID,
            userID: userID
        )

        resumeItems.elements = HomeItemUserDataOverrideStore.filteredResumeItems(
            resumeItems.elements,
            serverID: serverID,
            userID: userID,
            playedAncestorIDs: visiblePlayedItemIDs
        )

        nextUpViewModel.elements = Self.identifiedItems(
            HomeItemUserDataOverrideStore.filteredNextUpItems(
                Array(nextUpViewModel.elements),
                serverID: serverID,
                userID: userID,
                playedAncestorIDs: visiblePlayedItemIDs
            )
        )

        recentlyAddedViewModel.elements = Self.identifiedItems(recentlyAddedItems)

        for (library, items) in libraryItems {
            library.elements = Self.identifiedItems(items)
        }
    }

    @discardableResult
    private func applyCachedHomeStateIfAvailable() -> Bool {
        guard let userSession,
              let payload = HomeViewModelCacheStore.load(
                  serverID: userSession.server.id,
                  userID: userSession.user.id
              ) else {
            return false
        }

        resumeItems.elements = payload.resumeItems
        preheatResumeItemImages()

        nextUpViewModel.elements = Self.identifiedItems(payload.nextUpItems)
        nextUpViewModel.state = .content

        recentlyAddedViewModel.elements = Self.identifiedItems(payload.recentlyAddedItems)
        recentlyAddedViewModel.state = .content

        libraries = payload.libraries.map { cachedLibrary in
            let viewModel = LatestInLibraryViewModel(parent: cachedLibrary.parent)
            viewModel.elements = Self.identifiedItems(cachedLibrary.items)
            viewModel.state = .content
            return viewModel
        }

        state = .content

        return true
    }

    private func cacheCurrentHomeState() {
        guard let userSession else { return }

        let cachedLibraries = libraries.compactMap { viewModel -> HomeViewModelCachedLibrary? in
            guard let parent = viewModel.parent as? BaseItemDto else { return nil }

            return HomeViewModelCachedLibrary(
                parent: parent,
                items: Array(viewModel.elements)
            )
        }

        let payload = HomeViewModelCachePayload(
            serverID: userSession.server.id,
            userID: userSession.user.id,
            savedAt: Date(),
            resumeItems: Array(resumeItems),
            nextUpItems: Array(nextUpViewModel.elements),
            recentlyAddedItems: Array(recentlyAddedViewModel.elements),
            libraries: cachedLibraries
        )

        HomeViewModelCacheStore.save(payload)
    }

    private func preheatResumeItemImages() {
        let sources = resumeItems
            .prefix(6)
            .flatMap { item in
                item.landscapeImageSources(maxWidth: 300, quality: 90)
            }
            .compactMap(\.url)

        guard sources.isNotEmpty else { return }

        resumeImagePreheatTask?.cancel()
        resumeImagePreheatTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for url in sources.prefix(18) {
                    group.addTask {
                        _ = try? await ImagePipeline.Emby.posters.image(for: url)
                    }
                }
            }
        }
    }

    private static func identifiedItems(_ items: [BaseItemDto]) -> IdentifiedArray<Int, BaseItemDto> {
        IdentifiedArray(
            items,
            id: \.unwrappedIDHashOrZero,
            uniquingIDsWith: { lhs, _ in lhs }
        )
    }

    private static func hiddenHomeLibraryIDs() -> Set<String> {
        var ids = Set<String>()

        for sectionID in Defaults[.Customization.Home.hiddenSectionIDs] {
            if let libraryID = HomeSectionDescriptor.latestInLibrarySourceID(from: sectionID) {
                ids.insert(libraryID)
            }
        }

        return ids
    }

    private static func libraryIDs(from libraries: [LatestInLibraryViewModel]) -> [String] {
        var ids: [String] = []

        for library in libraries {
            guard let id = library.parent?.id else { continue }
            ids.append(id)
        }

        return uniqueIDs(ids)
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func uniqueItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
        var seen = Set<String>()

        return items.filter { item in
            guard let id = item.id, id.isNotEmpty else { return true }
            return seen.insert(id).inserted
        }
    }
}

private struct HomeViewModelCachePayload: Codable {
    let serverID: String
    let userID: String
    let savedAt: Date
    let resumeItems: [BaseItemDto]
    let nextUpItems: [BaseItemDto]
    let recentlyAddedItems: [BaseItemDto]
    let libraries: [HomeViewModelCachedLibrary]
}

private struct HomeViewModelCachedLibrary: Codable {
    let parent: BaseItemDto
    let items: [BaseItemDto]
}

private enum HomeViewModelCacheStore {

    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let directoryName = "HomeViewModelCache"

    static func load(serverID: String, userID: String) -> HomeViewModelCachePayload? {
        guard let url = cacheURL(serverID: serverID, userID: userID),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(HomeViewModelCachePayload.self, from: data),
              payload.serverID == serverID,
              payload.userID == userID,
              Date().timeIntervalSince(payload.savedAt) <= maxAge else {
            return nil
        }

        return payload
    }

    static func save(_ payload: HomeViewModelCachePayload) {
        guard let url = cacheURL(serverID: payload.serverID, userID: payload.userID) else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache failures should never block the home screen.
        }
    }

    private static func cacheURL(serverID: String, userID: String) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return cachesDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName(serverID: serverID, userID: userID))
    }

    private static func fileName(serverID: String, userID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let rawName = "\(serverID)_\(userID)"
        let safeName = rawName.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? String(scalar) : "_"
        }
        .joined()

        return "\(safeName).json"
    }
}

enum HomeRefreshInvalidationStore {

    private static let keyPrefix = "HomeRefreshInvalidation"

    static func markAndPostRelatedMetadataRefresh(for item: BaseItemDto, userSession: UserSession) {
        mark(serverID: userSession.server.id, userID: userSession.user.id)

        for id in relatedMetadataIDs(for: item) {
            Notifications[.itemShouldRefreshMetadata].post(id)
        }
    }

    static func mark(serverID: String, userID: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key(serverID: serverID, userID: userID))
    }

    static func consume(serverID: String, userID: String) -> Bool {
        let key = key(serverID: serverID, userID: userID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return true
    }

    static func hasPending(serverID: String, userID: String) -> Bool {
        UserDefaults.standard.object(forKey: key(serverID: serverID, userID: userID)) != nil
    }

    private static func key(serverID: String, userID: String) -> String {
        "\(keyPrefix).\(serverID).\(userID)"
    }

    private static func relatedMetadataIDs(for item: BaseItemDto) -> Set<String> {
        Set([
            item.id,
            item.parentID,
            item.seasonID,
            item.seriesID,
        ].compactMap { $0 })
    }
}

enum HomeItemUserDataOverrideStore {

    private struct Entry: Codable {
        let itemID: String
        let isPlayed: Bool
        let changedAt: TimeInterval
        let appliesToRelatedItems: Bool?

        var shouldApplyToRelatedItems: Bool {
            appliesToRelatedItems ?? true
        }
    }

    private static let keyPrefix = "HomeItemUserDataOverride"
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private static let parentOnlyMaxAge: TimeInterval = 60

    static func markPlayed(
        itemID: String,
        isPlayed: Bool,
        serverID: String,
        userID: String,
        appliesToRelatedItems: Bool = true
    ) {
        var entries = load(serverID: serverID, userID: userID)
        entries[itemID] = Entry(
            itemID: itemID,
            isPlayed: isPlayed,
            changedAt: Date().timeIntervalSince1970,
            appliesToRelatedItems: appliesToRelatedItems
        )
        save(entries, serverID: serverID, userID: userID)
    }

    static func markPlayed(
        item: BaseItemDto,
        isPlayed: Bool,
        serverID: String,
        userID: String
    ) {
        guard let itemID = item.id else { return }

        var entries = load(serverID: serverID, userID: userID)
        let changedAt = Date().timeIntervalSince1970

        entries[itemID] = Entry(
            itemID: itemID,
            isPlayed: isPlayed,
            changedAt: changedAt,
            appliesToRelatedItems: true
        )

        for ancestorID in watchedAncestorIDsAffectedByChildPlayback(for: item) {
            if isPlayed {
                if entries[ancestorID]?.shouldApplyToRelatedItems == false {
                    entries.removeValue(forKey: ancestorID)
                }
            } else {
                entries[ancestorID] = Entry(
                    itemID: ancestorID,
                    isPlayed: false,
                    changedAt: changedAt,
                    appliesToRelatedItems: false
                )
            }
        }

        save(entries, serverID: serverID, userID: userID)
    }

    static func clear(itemID: String?, serverID: String, userID: String) {
        guard let itemID else { return }

        var entries = load(serverID: serverID, userID: userID)
        entries.removeValue(forKey: itemID)
        save(entries, serverID: serverID, userID: userID)
    }

    static func clearRelatedItems(for item: BaseItemDto, serverID: String, userID: String) {
        var entries = load(serverID: serverID, userID: userID)

        for id in relatedIDs(for: item) {
            entries.removeValue(forKey: id)
        }

        save(entries, serverID: serverID, userID: userID)
    }

    static func filteredResumeItems(
        _ items: [BaseItemDto],
        serverID: String,
        userID: String,
        playedAncestorIDs: Set<String> = []
    ) -> [BaseItemDto] {
        let entries = load(serverID: serverID, userID: userID)

        return items
            .filter { item in
                entry(for: item, in: entries)?.isPlayed != true && !hasPlayedAncestor(item, in: playedAncestorIDs)
            }
            .map { applying(entries: entries, to: $0) }
    }

    static func filteredNextUpItems(
        _ items: [BaseItemDto],
        serverID: String,
        userID: String,
        playedAncestorIDs: Set<String> = []
    ) -> [BaseItemDto] {
        let entries = load(serverID: serverID, userID: userID)

        return items
            .filter { item in
                entry(for: item, in: entries)?.isPlayed != true && !hasPlayedAncestor(item, in: playedAncestorIDs)
            }
            .map { applying(entries: entries, to: $0) }
    }

    static func applyingOverrides(
        to items: [BaseItemDto],
        serverID: String,
        userID: String
    ) -> [BaseItemDto] {
        let entries = load(serverID: serverID, userID: userID)
        return items.map { applying(entries: entries, to: $0) }
    }

    static func applyingOverrides(
        to item: BaseItemDto,
        serverID: String,
        userID: String
    ) -> BaseItemDto {
        let entries = load(serverID: serverID, userID: userID)
        return applying(entries: entries, to: item)
    }

    static func applyingItemOnlyOverride(
        to item: BaseItemDto,
        serverID: String,
        userID: String
    ) -> BaseItemDto {
        let entries = load(serverID: serverID, userID: userID)
        guard let itemID = item.id, let entry = entries[itemID] else { return item }
        return applyingPlayedState(entry.isPlayed, to: item)
    }

    static func applyingItemOnlyOverrides(
        to items: [BaseItemDto],
        serverID: String,
        userID: String
    ) -> [BaseItemDto] {
        let entries = load(serverID: serverID, userID: userID)
        return items.map { item in
            guard let itemID = item.id, let entry = entries[itemID] else { return item }
            return applyingPlayedState(entry.isPlayed, to: item)
        }
    }

    static func latestChangedItemID(
        in itemIDs: [String],
        serverID: String,
        userID: String
    ) -> String? {
        let entries = load(serverID: serverID, userID: userID)
        let itemIDSet = Set(itemIDs)

        return entries.values
            .filter { itemIDSet.contains($0.itemID) }
            .max { $0.changedAt < $1.changedAt }?
            .itemID
    }

    static func playedItemIDs(
        in items: [BaseItemDto],
        serverID: String,
        userID: String
    ) -> Set<String> {
        let entries = load(serverID: serverID, userID: userID)

        return Set(
            items.compactMap { item in
                guard applying(entries: entries, to: item).userData?.isPlayed == true else { return nil }
                return item.id
            }
        )
    }

    static func applyingPlayedState(_ isPlayed: Bool, to item: BaseItemDto) -> BaseItemDto {
        var copy = item
        var userData = copy.userData ?? UserItemDataDto()

        userData.isPlayed = isPlayed
        userData.playbackPositionTicks = 0
        userData.playedPercentage = isPlayed ? 100 : 0
        userData.lastPlayedDate = isPlayed ? Date() : nil

        if isPlayed {
            userData.playCount = max(userData.playCount ?? 0, 1)
        } else {
            userData.playCount = 0
        }

        copy.userData = userData
        return copy
    }

    private static func applying(entries: [String: Entry], to item: BaseItemDto) -> BaseItemDto {
        guard let entry = entry(for: item, in: entries) else { return item }
        return applyingPlayedState(entry.isPlayed, to: item)
    }

    private static func entry(for item: BaseItemDto, in entries: [String: Entry]) -> Entry? {
        let itemID = item.id

        return relatedIDs(for: item)
            .compactMap { id -> Entry? in
                guard let entry = entries[id] else { return nil }
                guard id == itemID || entry.shouldApplyToRelatedItems else { return nil }
                return entry
            }
            .max { $0.changedAt < $1.changedAt }
    }

    private static func hasPlayedAncestor(_ item: BaseItemDto, in playedAncestorIDs: Set<String>) -> Bool {
        relatedIDs(for: item).contains { playedAncestorIDs.contains($0) }
    }

    private static func relatedIDs(for item: BaseItemDto) -> [String] {
        [
            item.id,
            item.parentID,
            item.seasonID,
            item.seriesID,
        ].compactMap { $0 }
    }

    private static func watchedAncestorIDsAffectedByChildPlayback(for item: BaseItemDto) -> [String] {
        switch item.type {
        case .episode:
            return uniqueIDs([
                item.seasonID,
                item.parentID,
                item.seriesID,
            ], excluding: item.id)
        case .season:
            return uniqueIDs([
                item.seriesID,
                item.parentID,
            ], excluding: item.id)
        default:
            return []
        }
    }

    private static func uniqueIDs(_ ids: [String?], excluding excludedID: String?) -> [String] {
        var seen = Set<String>()

        return ids.compactMap { id in
            guard let id, id.isNotEmpty, id != excludedID, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private static func load(serverID: String, userID: String) -> [String: Entry] {
        let storageKey = key(serverID: serverID, userID: userID)
        let now = Date().timeIntervalSince1970
        let data = UserDefaults.standard.data(forKey: storageKey)
        var entries = data
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]

        entries = entries.filter { _, entry in
            let maxEntryAge = entry.shouldApplyToRelatedItems ? maxAge : parentOnlyMaxAge
            return now - entry.changedAt <= maxEntryAge
        }
        save(entries, serverID: serverID, userID: userID)

        return entries
    }

    private static func save(_ entries: [String: Entry], serverID: String, userID: String) {
        let storageKey = key(serverID: serverID, userID: userID)

        guard entries.isNotEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func key(serverID: String, userID: String) -> String {
        "\(keyPrefix).\(serverID).\(userID)"
    }
}

enum ResumeItemRecencyStore {

    private static let maxEntries = 300

    static func markPlayback(
        itemID: String?,
        serverID: String,
        userID: String,
        at date: Date = Date()
    ) {
        guard let itemID, itemID.isNotEmpty else { return }

        let key = storageKey(serverID: serverID, userID: userID)
        var values = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        values[itemID] = date.timeIntervalSince1970

        if values.count > maxEntries {
            values = Dictionary(
                uniqueKeysWithValues: values
                    .sorted { $0.value > $1.value }
                    .prefix(maxEntries)
                    .map { ($0.key, $0.value) }
            )
        }

        UserDefaults.standard.set(values, forKey: key)
    }

    static func sorted(
        _ items: [BaseItemDto],
        serverID: String,
        userID: String
    ) -> [BaseItemDto] {
        let values = UserDefaults.standard.dictionary(
            forKey: storageKey(serverID: serverID, userID: userID)
        ) as? [String: TimeInterval] ?? [:]

        return items
            .enumerated()
            .sorted { lhs, rhs in
                let lhsLastPlayed = lastPlayedDate(for: lhs.element, values: values)
                let rhsLastPlayed = lastPlayedDate(for: rhs.element, values: values)

                switch (lhsLastPlayed, rhsLastPlayed) {
                case let (lhsLastPlayed?, rhsLastPlayed?) where lhsLastPlayed != rhsLastPlayed:
                    return lhsLastPlayed > rhsLastPlayed
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func lastPlayedDate(for item: BaseItemDto, values: [String: TimeInterval]) -> Date? {
        let storedDate = item.id.flatMap { values[$0] }.map(Date.init(timeIntervalSince1970:))
        guard let serverDate = item.userData?.lastPlayedDate else {
            return storedDate
        }
        guard let storedDate else {
            return serverDate
        }
        return max(storedDate, serverDate)
    }

    private static func storageKey(serverID: String, userID: String) -> String {
        "EmbyResumeItemRecency.\(serverID).\(userID)"
    }
}

extension HomeViewModel {

    private func getLibraries() async throws -> [LatestInLibraryViewModel] {

        async let userViews: EmbyPortItemsResponse<BaseItemDto> = userSession.embyClient.userViews(
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )
        async let excludedLibraryIDs = getExcludedLibraries()

        let views = try await userViews

        return try await (views.items ?? [])
            .intersecting(
                [
                    .homevideos,
                    .movies,
                    .musicvideos,
                    .tvshows,
                ],
                using: \.collectionType
            )
            .subtracting(excludedLibraryIDs, using: \.id)
            .map { LatestInLibraryViewModel(parent: $0) }
    }

    // TODO: use the more updated server/user data when implemented
    private func getExcludedLibraries() async throws -> [String] {
        let response: EmbyPortCurrentUserResponse = try await userSession.embyClient.currentUser(
            as: EmbyPortCurrentUserResponse.self
        )

        return response.configuration?.latestItemsExcludes ?? []
    }

    private func setIsPlayed(_ isPlayed: Bool, for item: BaseItemDto) async throws {
        guard let itemID = item.id else { return }
        try await userSession.embyClient.setPlayed(isPlayed, itemID: itemID)
        try? await userSession.embyClient.clearPlaybackProgress(itemID: itemID)
        HomeItemUserDataOverrideStore.markPlayed(
            item: item,
            isPlayed: isPlayed,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
        HomeRefreshInvalidationStore.markAndPostRelatedMetadataRefresh(for: item, userSession: userSession)
    }
}
