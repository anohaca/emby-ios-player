//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Factory
import Foundation
import IdentifiedCollections
import OrderedCollections

@MainActor
final class HomeViewModel: ViewModel, Stateful {

    // MARK: Action

    enum Action: Equatable {
        case backgroundRefresh
        case error(ErrorMessage)
        case setIsPlayed(Bool, BaseItemDto)
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
    private var refreshTask: AnyCancellable?

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
                    self?.notificationsReceived.insert(.itemMetadataDidChange)
                }
            }
            .store(in: &cancellables)

        Notifications[.resumeItemRecencyDidChange]
            .publisher
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.notificationsReceived.insert(.resumeItemRecencyDidChange)
                    self.reorderResumeItemsFromLocalRecency()

                    if self.state == .content {
                        self.send(.backgroundRefresh)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func respond(to action: Action) -> State {
        switch action {
        case .backgroundRefresh:

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
        case let .setIsPlayed(isPlayed, item): ()
            Task {
                try await setIsPlayed(isPlayed, for: item)

                self.send(.backgroundRefresh)
            }
            .store(in: &cancellables)

            return state
        case .refresh:
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

        try await refreshLibrary(nextUpViewModel)
        try await refreshLibrary(recentlyAddedViewModel)

        let resumeItems = try await getResumeItems()
        let libraries = try await getLibraries()

        for library in libraries {
            try await refreshLibrary(library)
        }

        await MainActor.run {
            self.resumeItems.elements = resumeItems
            self.libraries = libraries
            self.cacheCurrentHomeState()
        }
    }

    private func refreshLibrary(_ viewModel: PagingLibraryViewModel<BaseItemDto>) async throws {
        try await viewModel.refresh()
        viewModel.state = .content
    }

    private func getResumeItems() async throws -> [BaseItemDto] {
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.resumeItems(
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return ResumeItemRecencyStore.sorted(
            response.items ?? [],
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func reorderResumeItemsFromLocalRecency() {
        resumeItems.elements = ResumeItemRecencyStore.sorted(
            resumeItems.elements,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
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

    private static func identifiedItems(_ items: [BaseItemDto]) -> IdentifiedArray<Int, BaseItemDto> {
        IdentifiedArray(
            items,
            id: \.unwrappedIDHashOrZero,
            uniquingIDsWith: { lhs, _ in lhs }
        )
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
    }
}
