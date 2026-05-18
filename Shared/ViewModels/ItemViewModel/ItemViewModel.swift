//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Factory
import Foundation
import OrderedCollections
import UIKit

// TODO: come up with a cleaner, more defined way for item update notifications

class ItemViewModel: ViewModel, Stateful {

    // MARK: Action

    enum Action: Equatable {
        case backgroundRefresh
        case error(ErrorMessage)
        case refresh
        case replace(BaseItemDto)
        case toggleIsFavorite
        case toggleIsPlayed
        case applyDefaultTrackSelection
        case selectAudioStream(Int?)
        case selectMediaSource(MediaSourceInfo)
        case selectSubtitleStream(Int?)
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

    // TODO: create value on `BaseItemDto` whether an item
    //       only has children as playable items
    @Published
    private(set) var item: BaseItemDto {
        willSet {
            if item.isPlayable {
                playButtonItem = newValue
            }
        }
    }

    @Published
    var playButtonItem: BaseItemDto? {
        willSet {
            if let newValue {
                selectMediaSource(newValue.mediaSources?.first)
            }
        }
    }

    @Published
    private(set) var selectedMediaSource: MediaSourceInfo?
    @Published
    private(set) var selectedAudioStreamIndex: Int?
    @Published
    private(set) var selectedSubtitleStreamIndex: Int?
    @Published
    private(set) var similarItems: [BaseItemDto] = []
    @Published
    private(set) var specialFeatures: [BaseItemDto] = []
    @Published
    private(set) var localTrailers: [BaseItemDto] = []
    @Published
    private(set) var additionalParts: [BaseItemDto] = []

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var state: State = .initial

    private var itemID: String {
        get throws {
            guard let id = item.id else {
                logger.error("Item ID is nil")
                throw ErrorMessage(L10n.unknownError)
            }
            return id
        }
    }

    // tasks

    private var toggleIsFavoriteTask: AnyCancellable?
    private var toggleIsPlayedTask: AnyCancellable?
    private var refreshTask: AnyCancellable?

    // MARK: init

    @MainActor
    init(item: BaseItemDto) {
        self.item = item
        super.init()

        let overriddenItem = applyingUserDataOverrides(to: item)
        if overriddenItem != item {
            self.item = overriddenItem
        }

        Notifications[.itemShouldRefreshMetadata]
            .publisher
            .sink { [weak self] itemID in
                guard itemID == self?.item.id else { return }

                Task {
                    await self?.send(.backgroundRefresh)
                }
            }
            .store(in: &cancellables)

        Notifications[.itemMetadataDidChange]
            .publisher
            .sink { [weak self] newItem in
                guard let newItemID = newItem.id, newItemID == self?.item.id else { return }

                Task {
                    await self?.send(.replace(newItem))
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    convenience init(episode: BaseItemDto) {
        let shellSeriesItem = BaseItemDto(id: episode.seriesID, name: episode.seriesName)
        self.init(item: shellSeriesItem)
    }

    // MARK: respond

    func respond(to action: Action) -> State {
        switch action {
        case .backgroundRefresh:

            backgroundStates.insert(.refresh)

            Task { [weak self] in
                guard let self else { return }
                do {
                    async let fullItem = getFullItem()
                    async let similarItems = getSimilarItems()
                    async let specialFeatures = getSpecialFeatures()
                    async let localTrailers = getLocalTrailers()

                    let results = try await (
                        fullItem: fullItem,
                        similarItems: similarItems,
                        specialFeatures: specialFeatures,
                        localTrailers: localTrailers
                    )

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        let fullItem = self.applyingUserDataOverrides(to: results.fullItem)
                        self.backgroundStates.remove(.refresh)
                        if fullItem.id != self.item.id || fullItem != self.item {
                            self.item = fullItem
                        }

                        if !results.similarItems.elementsEqual(self.similarItems, by: { $0.id == $1.id }) {
                            self.similarItems = results.similarItems
                        }

                        if !results.specialFeatures.elementsEqual(self.specialFeatures, by: { $0.id == $1.id }) {
                            self.specialFeatures = results.specialFeatures
                        }

                        if !results.localTrailers.elementsEqual(self.localTrailers, by: { $0.id == $1.id }) {
                            self.localTrailers = results.localTrailers
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.logger.error("Item background refresh failed: \(error.embyDiagnosticDescription)")
                        if self.state != .content {
                            self.send(.error(.init(error.embyDisplayDescription)))
                        }
                    }
                }
            }
            .store(in: &cancellables)

            return state
        case let .error(error):
            return .error(error)
        case .refresh:

            refreshTask?.cancel()

            refreshTask = Task { [weak self] in
                guard let self else { return }
                do {
                    async let fullItem = getFullItem()
                    async let similarItems = getSimilarItems()
                    async let specialFeatures = getSpecialFeatures()
                    async let localTrailers = getLocalTrailers()
                    async let additionalParts = getAdditionalParts()

                    let results = try await (
                        fullItem: fullItem,
                        similarItems: similarItems,
                        specialFeatures: specialFeatures,
                        localTrailers: localTrailers,
                        additionalParts: additionalParts
                    )

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.item = self.applyingUserDataOverrides(to: results.fullItem)
                        self.similarItems = results.similarItems
                        self.specialFeatures = results.specialFeatures
                        self.localTrailers = results.localTrailers
                        self.additionalParts = results.additionalParts

                        self.state = .content
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.logger.error("Item refresh failed: \(error.embyDiagnosticDescription)")
                        if self.state != .content {
                            self.send(.error(.init(error.embyDisplayDescription)))
                        }
                    }
                }
            }
            .asAnyCancellable()

            return .refreshing
        case let .replace(newItem):

            backgroundStates.insert(.refresh)

            Task { [weak self] in
                guard let self else { return }
                do {
                    await MainActor.run {
                        self.backgroundStates.remove(.refresh)
                        self.item = self.applyingUserDataOverrides(to: newItem)
                    }
                }
            }
            .store(in: &cancellables)

            return state
        case .toggleIsFavorite:

            toggleIsFavoriteTask?.cancel()

            toggleIsFavoriteTask = Task {

                let beforeIsFavorite = item.userData?.isFavorite ?? false

                await MainActor.run {
                    item.userData?.isFavorite?.toggle()
                }

                do {
                    try await setIsFavorite(!beforeIsFavorite)
                } catch {
                    await MainActor.run {
                        item.userData?.isFavorite = beforeIsFavorite
                        // emit event that toggle unsuccessful
                    }
                }
            }
            .asAnyCancellable()

            return state
        case .toggleIsPlayed:

            toggleIsPlayedTask?.cancel()

            toggleIsPlayedTask = Task {

                let beforeIsPlayed = item.userData?.isPlayed ?? false
                let newIsPlayed = !beforeIsPlayed

                await MainActor.run {
                    item = HomeItemUserDataOverrideStore.applyingPlayedState(newIsPlayed, to: item)
                }

                HomeItemUserDataOverrideStore.markPlayed(
                    item: item,
                    isPlayed: newIsPlayed,
                    serverID: userSession.server.id,
                    userID: userSession.user.id
                )
                notifyHomeAndRelatedItemsShouldRefresh()

                do {
                    try await setIsPlayed(newIsPlayed)
                } catch {
                    await MainActor.run {
                        item = HomeItemUserDataOverrideStore.applyingPlayedState(beforeIsPlayed, to: item)
                        // emit event that toggle unsuccessful
                    }
                    HomeItemUserDataOverrideStore.markPlayed(
                        item: item,
                        isPlayed: beforeIsPlayed,
                        serverID: userSession.server.id,
                        userID: userSession.user.id
                    )
                    notifyHomeAndRelatedItemsShouldRefresh()
                }
            }
            .asAnyCancellable()

            return state
        case .applyDefaultTrackSelection:

            applyDefaultTrackSelection()

            return state
        case let .selectAudioStream(index):

            selectedAudioStreamIndex = index

            return state
        case let .selectMediaSource(newSource):

            selectMediaSource(newSource)

            return state
        case let .selectSubtitleStream(index):

            selectedSubtitleStreamIndex = index

            return state
        }
    }

    private func selectMediaSource(_ mediaSource: MediaSourceInfo?) {
        selectedMediaSource = mediaSource
        applyDefaultTrackSelection()
    }

    private func applyDefaultTrackSelection() {
        selectedAudioStreamIndex = MediaTrackDefaults.selectedAudioStreamIndex(in: selectedMediaSource)
        selectedSubtitleStreamIndex = MediaTrackDefaults.selectedSubtitleStreamIndex(in: selectedMediaSource)

        #if DEBUG
        let audioTitle = selectedMediaSource?.audioStreams?.first { $0.index == selectedAudioStreamIndex }?.displayTitle ?? "<nil>"
        let subtitleTitle = selectedMediaSource?.subtitleStreams?.first { $0.index == selectedSubtitleStreamIndex }?.displayTitle ?? "<nil>"
        logger.info(
            """
            ITEM_DEFAULT_TRACK_SELECTION audioPreference=\(Defaults[.VideoPlayer.Playback.defaultAudioLanguage].displayTitle) selectedAudioIndex=\(selectedAudioStreamIndex ?? -999) audioTitle=\(audioTitle) subtitlePreference=\(Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage].displayTitle) selectedSubtitleIndex=\(selectedSubtitleStreamIndex ?? -999) subtitleTitle=\(subtitleTitle)
            """
        )
        #endif
    }

    private func getFullItem() async throws -> BaseItemDto {
        try await item.getFullItem(userSession: userSession, sendNotification: true)
    }

    private func getSimilarItems() async -> [BaseItemDto] {

        var parameters = EmbyPortSimilarItemsParameters()
        parameters.fields = .MinimumFields
        parameters.limit = 20

        let response: EmbyPortItemsResponse<BaseItemDto>? = try? await userSession.embyClient.similarItems(
            itemID: item.id!,
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response?.items ?? []
    }

    private func getSpecialFeatures() async -> [BaseItemDto] {

        let response: [BaseItemDto]? = try? await userSession.embyClient.specialFeatures(
            itemID: item.id!,
            as: [BaseItemDto].self
        )

        return (response ?? [])
            .filter { $0.extraType?.isVideo ?? false }
    }

    private func getLocalTrailers() async throws -> [BaseItemDto] {

        let response: [BaseItemDto]? = try? await userSession.embyClient.localTrailers(
            itemID: itemID,
            as: [BaseItemDto].self
        )

        return response ?? []
    }

    private func getAdditionalParts() async throws -> [BaseItemDto] {

        guard let partCount = item.partCount,
              partCount > 1,
              let itemID = item.id else { return [] }

        let response: EmbyPortItemsResponse<BaseItemDto>? = try? await userSession.embyClient.additionalParts(
            itemID: itemID,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response?.items ?? []
    }

    private func applyingUserDataOverrides(to item: BaseItemDto) -> BaseItemDto {
        guard let userSession else { return item }

        return HomeItemUserDataOverrideStore.applyingOverrides(
            to: item,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {

        guard let itemID = item.id else { return }

        try await userSession.embyClient.setPlayed(isPlayed, itemID: itemID)
        try? await userSession.embyClient.clearPlaybackProgress(itemID: itemID)
        HomeItemUserDataOverrideStore.markPlayed(
            item: item,
            isPlayed: isPlayed,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
        notifyHomeAndRelatedItemsShouldRefresh()
    }

    private func setIsFavorite(_ isFavorite: Bool) async throws {

        guard let itemID = item.id else { return }

        try await userSession.embyClient.setFavorite(isFavorite, itemID: itemID)
        notifyHomeAndRelatedItemsShouldRefresh()
    }

    private func notifyHomeAndRelatedItemsShouldRefresh() {
        HomeRefreshInvalidationStore.markAndPostRelatedMetadataRefresh(for: item, userSession: userSession)
    }
}
