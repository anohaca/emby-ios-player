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
import IdentifiedCollections

// TODO: care for one long episodes list?
//       - after SeasonItemViewModel is bidirectional
//       - would have to see if server returns right amount of episodes/season
final class SeriesItemViewModel: ItemViewModel {

    @Published
    var seasons: IdentifiedArrayOf<SeasonItemViewModel> = []

    private let seedEpisode: BaseItemDto?
    private var didLoadAllSeasons = false

    // MARK: - Task

    private var seriesItemTask: AnyCancellable?

    // MARK: - Init

    @MainActor
    override init(item: BaseItemDto) {
        self.seedEpisode = nil
        super.init(item: item)
        observeLoadedEpisodePlaybackChanges()
    }

    @MainActor
    init(episode: BaseItemDto) {
        self.seedEpisode = episode

        let shellSeriesItem = BaseItemDto(
            id: episode.seriesID,
            name: episode.seriesName,
            type: .series
        )

        super.init(item: shellSeriesItem)
        observeLoadedEpisodePlaybackChanges()

        playButtonItem = episode
        ensureSeedSeason(refresh: true)
    }

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .backgroundRefresh, .refresh:
            let parentState = super.respond(to: action)

            seriesItemTask?.cancel()

            Task { [weak self] in
                guard let self else { return }

                let existingSeasons: [String: SeasonItemViewModel] = await MainActor.run {
                    if self.seedEpisode != nil {
                        self.ensureSeedSeason(refresh: true)
                    }

                    return Dictionary<String, SeasonItemViewModel>(
                        uniqueKeysWithValues: self.seasons.compactMap { seasonViewModel in
                            guard let id = seasonViewModel.id else { return nil }
                            return (id, seasonViewModel)
                        }
                    )
                }

                do {
                    async let nextUp = getNextUp()
                    async let resume = getResumeItem()
                    async let firstUnplayed = getFirstUnplayedItem()
                    async let firstAvailable = getFirstAvailableItem()
                    async let latestChanged = getLatestChangedEpisodeItem()
                    async let seasons = getSeasons()

                    let newSeasons = try await seasons
                        .sorted { ($0.indexNumber ?? -1) < ($1.indexNumber ?? -1) }
                        .map { season in
                            if let id = season.id, let existingSeason = existingSeasons[id] {
                                existingSeason
                            } else {
                                SeasonItemViewModel(season: season, seriesID: self.item.id)
                            }
                        }

                    await MainActor.run {
                        self.seasons = IdentifiedArray(uniqueElements: newSeasons)
                        self.didLoadAllSeasons = true
                        self.ensureSeedSeason(refresh: true)
                        self.refreshSeasonIfNeeded(for: self.seedEpisode ?? self.playButtonItem)
                        self.refreshPlayedPlayButtonItemFromLoadedEpisodes()
                    }

                    let episodeItem = try await preferredPlayButtonItem(
                        nextUp: nextUp,
                        resume: resume,
                        firstUnplayed: firstUnplayed,
                        latestChanged: latestChanged,
                        firstAvailable: firstAvailable
                    )

                    if let episodeItem {
                        await MainActor.run {
                            self.updatePlayButtonItemIfNeeded(episodeItem)
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        self.logger.error("Series refresh failed: \(error.embyDiagnosticDescription)")
                    }
                }
            }
            .store(in: &cancellables)

            return parentState
        default: ()
        }

        return super.respond(to: action)
    }

    @MainActor
    private func ensureSeedSeason(refresh: Bool) {
        guard let seedEpisode else { return }
        guard let seasonID = seedEpisode.seasonID else { return }
        guard let seriesID = seedEpisode.seriesID else { return }

        let seasonViewModel: SeasonItemViewModel

        if let existingSeasonViewModel = seasons[id: seasonID] {
            seasonViewModel = existingSeasonViewModel
        } else {
            let seasonName = seedEpisode.seasonName
                ?? seedEpisode.parentIndexNumber.map { "\(L10n.season) \($0)" }
                ?? L10n.season
            let season = BaseItemDto(
                id: seasonID,
                indexNumber: seedEpisode.parentIndexNumber,
                name: seasonName,
                parentID: seriesID,
                seriesID: seriesID,
                type: .season
            )

            seasonViewModel = SeasonItemViewModel(season: season, seriesID: seriesID)
            seasons.append(seasonViewModel)
        }

        if refresh, seasonViewModel.state == .initial {
            seasonViewModel.send(.refresh)
        }
    }

    @MainActor
    private func refreshSeasonIfNeeded(for item: BaseItemDto?) {
        let seasonViewModel: SeasonItemViewModel?
        if let seasonID = item?.seasonID {
            seasonViewModel = seasons.first(where: { $0.id == seasonID }) ?? seasons.first
        } else {
            seasonViewModel = seasons.first
        }

        guard let seasonViewModel, seasonViewModel.state == .initial else { return }
        seasonViewModel.send(.refresh)
    }

    private func observeLoadedEpisodePlaybackChanges() {
        Notifications[.itemShouldRefreshMetadata]
            .publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] itemID in
                Task { @MainActor [weak self] in
                    guard let self, self.loadedEpisodesContainRelatedItem(itemID) else { return }
                    self.refreshPlayedPlayButtonItemFromLoadedEpisodes(changedItemID: itemID)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func loadedEpisodesContainRelatedItem(_ itemID: String) -> Bool {
        itemID == item.id ||
            seasons.contains { season in
                season.id == itemID ||
                    season.elements.contains {
                        $0.id == itemID || $0.parentID == itemID || $0.seasonID == itemID || $0.seriesID == itemID
                    }
            }
    }

    @MainActor
    private func refreshPlayedPlayButtonItemFromLoadedEpisodes(changedItemID: String? = nil) {
        let currentPlayButtonItem = playButtonItem.map { applyingEpisodeUserDataOverrides(to: $0) }
        let loadedEpisodes = seasons.flatMap { Array($0.elements) }
        guard loadedEpisodes.isNotEmpty else {
            updatePlayButtonItemIfNeeded(currentPlayButtonItem)
            return
        }

        let sortedEpisodes = applyingEpisodeUserDataOverrides(to: loadedEpisodes)
            .filter { !$0.isMissing }
            .sorted(by: episodePlaybackOrder)
        let allEpisodesPlayed = sortedEpisodes.isNotEmpty && sortedEpisodes.allSatisfy { $0.userData?.isPlayed == true }

        refreshParentPlayedStateFromLoadedEpisodes(sortedEpisodes)

        if allEpisodesPlayed {
            updatePlayButtonItemIfNeeded(sortedEpisodes.last)
            return
        }

        let changedEpisode = changedItemID.flatMap { itemID in
            sortedEpisodes.first { $0.id == itemID }
        }

        if let changedEpisode {
            let episodeItem: BaseItemDto

            if changedEpisode.userData?.isPlayed == true {
                episodeItem = firstUnplayedEpisode(after: changedEpisode, in: sortedEpisodes) ?? changedEpisode
            } else {
                episodeItem = changedEpisode
            }

            updatePlayButtonItemIfNeeded(episodeItem)
            return
        }

        guard currentPlayButtonItem == nil || currentPlayButtonItem?.userData?.isPlayed == true else {
            updatePlayButtonItemIfNeeded(currentPlayButtonItem)
            return
        }

        guard let episodeItem = firstUnplayedEpisode(after: currentPlayButtonItem, in: sortedEpisodes)
            ?? (currentPlayButtonItem == nil ? (sortedEpisodes.first(where: { $0.userData?.isPlayed != true }) ?? sortedEpisodes.first) : nil)
        else {
            updatePlayButtonItemIfNeeded(currentPlayButtonItem)
            return
        }

        updatePlayButtonItemIfNeeded(episodeItem)
    }

    @MainActor
    private func updatePlayButtonItemIfNeeded(_ episodeItem: BaseItemDto?) {
        let episodeItem = playButtonItemAlignedWithLoadedEpisodes(episodeItem)
        guard episodeItem != playButtonItem else { return }
        playButtonItem = episodeItem
        refreshSeasonIfNeeded(for: episodeItem)
    }

    @MainActor
    private func playButtonItemAlignedWithLoadedEpisodes(_ episodeItem: BaseItemDto?) -> BaseItemDto? {
        guard let episodeItem else { return nil }

        let sortedEpisodes = applyingEpisodeUserDataOverrides(to: seasons.flatMap { Array($0.elements) })
            .filter { !$0.isMissing }
            .sorted(by: episodePlaybackOrder)
        guard sortedEpisodes.isNotEmpty else { return episodeItem }

        let loadedCandidate = sortedEpisodes.first { $0.id == episodeItem.id }
        let candidate = loadedCandidate ?? applyingEpisodeUserDataOverrides(to: episodeItem)

        guard let earlierVisibleUnplayed = sortedEpisodes.first(where: { visibleEpisode in
            visibleEpisode.userData?.isPlayed != true &&
                visibleEpisode.id != candidate.id &&
                episodePlaybackOrder(visibleEpisode, candidate)
        }) else {
            return candidate
        }

        refreshSeason(for: earlierVisibleUnplayed)

        #if DEBUG
        NSLog(
            "EmbySeriesPlayButton align candidate=%@ visible-unplayed=%@",
            candidate.seasonEpisodeLabel ?? candidate.displayTitle,
            earlierVisibleUnplayed.seasonEpisodeLabel ?? earlierVisibleUnplayed.displayTitle
        )
        #endif

        return earlierVisibleUnplayed
    }

    @MainActor
    private func refreshParentPlayedStateFromLoadedEpisodes(_ sortedEpisodes: [BaseItemDto]) {
        guard let seriesID = item.id, seriesID.isNotEmpty else { return }
        guard didLoadAllSeasons else { return }
        guard sortedEpisodes.isNotEmpty else { return }
        guard allKnownSeasonsAreLoaded(in: sortedEpisodes) else { return }
        guard sortedEpisodes.allSatisfy({ $0.userData?.isPlayed == true }) else { return }
        guard applyingUserDataOverrides(to: item).userData?.isPlayed != true else { return }

        HomeItemUserDataOverrideStore.markPlayed(
            itemID: seriesID,
            isPlayed: true,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )

        send(.replace(HomeItemUserDataOverrideStore.applyingPlayedState(true, to: item)))
        HomeRefreshInvalidationStore.markAndPostRelatedMetadataRefresh(for: item, userSession: userSession)
    }

    private func allKnownSeasonsAreLoaded(in episodes: [BaseItemDto]) -> Bool {
        let knownSeasonIDs = Set(seasons.compactMap(\.id))
        guard knownSeasonIDs.isNotEmpty else { return false }

        let loadedSeasonIDs = Set(
            episodes.compactMap { episode in
                episode.seasonID ?? episode.parentID
            }
        )

        return knownSeasonIDs.isSubset(of: loadedSeasonIDs)
    }

    // MARK: - Get Next Up Item

    private func getNextUp() async throws -> BaseItemDto? {

        var parameters = EmbyPortNextUpParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.seriesID = item.id

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.nextUp(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        guard let item = response.items?.first, !item.isMissing else {
            return nil
        }

        return applyingEpisodeUserDataOverrides(to: item)
    }

    // MARK: - Get First Unplayed Item

    private func getFirstUnplayedItem() async throws -> BaseItemDto? {

        guard let seriesID = item.id else { return nil }

        let parameters = EmbyPortEpisodesParameters(
            enableUserData: true,
            fields: .MinimumFields,
            isMissing: false,
            userID: userSession.user.id
        )
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.episodes(
            seriesID: seriesID,
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return applyingEpisodeUserDataOverrides(to: response.items ?? [])
            .sorted(by: episodePlaybackOrder)
            .first { !$0.isMissing && $0.userData?.isPlayed != true }
    }

    // MARK: - Get Resumable Item

    private func getLatestChangedEpisodeItem() async throws -> BaseItemDto? {

        guard let seriesID = item.id else { return nil }

        let parameters = EmbyPortEpisodesParameters(
            enableUserData: true,
            fields: .MinimumFields,
            isMissing: false,
            userID: userSession.user.id
        )
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.episodes(
            seriesID: seriesID,
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let episodes = applyingEpisodeUserDataOverrides(to: response.items ?? [])
            .filter { !$0.isMissing }
            .sorted(by: episodePlaybackOrder)

        if let latestChangedID = HomeItemUserDataOverrideStore.latestChangedItemID(
            in: episodes.compactMap(\.id),
            serverID: userSession.server.id,
            userID: userSession.user.id
        ),
            let latestChangedEpisode = episodes.first(where: { $0.id == latestChangedID })
        {
            return latestChangedEpisode
        }

        return episodes.last { $0.userData?.isPlayed == true }
    }

    // MARK: - Get Resumable Item

    private func getResumeItem() async throws -> BaseItemDto? {

        var parameters = EmbyPortResumeItemsParameters()
        parameters.fields = .MinimumFields
        parameters.limit = 1
        parameters.parentID = item.id

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.resumeItems(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items?.first.map { applyingEpisodeUserDataOverrides(to: $0) }
    }

    // MARK: - Get First Available Item

    private func getFirstAvailableItem() async throws -> BaseItemDto? {

        var parameters = EmbyPortItemsParameters()
        parameters.fields = .MinimumFields
        parameters.enableUserData = true
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortBy = [.parentIndexNumber, .indexNumber]
        parameters.sortOrder = [.ascending]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items?.first.map { applyingEpisodeUserDataOverrides(to: $0) }
    }

    private func preferredPlayButtonItem(
        nextUp: BaseItemDto?,
        resume: BaseItemDto?,
        firstUnplayed: BaseItemDto?,
        latestChanged: BaseItemDto?,
        firstAvailable: BaseItemDto?
    ) -> BaseItemDto? {

        let currentPlayButtonItem = playButtonItem.map { applyingEpisodeUserDataOverrides(to: $0) }
        let candidates = [nextUp, resume, firstUnplayed].compacted()
            .map { applyingEpisodeUserDataOverrides(to: $0) }
            .filter { !$0.isMissing && $0.userData?.isPlayed != true }

        let latestChangedEpisode = latestChanged.map { applyingEpisodeUserDataOverrides(to: $0) }

        if let currentPlayButtonItem, currentPlayButtonItem.userData?.isPlayed == true {
            if let laterCandidate = candidates.first(where: { episodePlaybackOrder(currentPlayButtonItem, $0) }) {
                return laterCandidate
            }

            if let latestChangedEpisode,
               !latestChangedEpisode.isMissing,
               shouldPreferLatestChangedEpisode(latestChangedEpisode, over: currentPlayButtonItem)
            {
                return latestChangedEpisode
            }

            return currentPlayButtonItem.isMissing ? nil : currentPlayButtonItem
        }

        if let candidate = candidates.first {
            return candidate
        }

        if let currentPlayButtonItem, !currentPlayButtonItem.isMissing {
            return currentPlayButtonItem
        }

        if let latestChangedEpisode,
           !latestChangedEpisode.isMissing
        {
            return latestChangedEpisode
        }

        if applyingUserDataOverrides(to: item).userData?.isPlayed == true {
            return nil
        }

        return [firstAvailable, nextUp, resume].compacted()
            .map { applyingEpisodeUserDataOverrides(to: $0) }
            .first { !$0.isMissing }
    }

    private func firstUnplayedEpisode(after currentItem: BaseItemDto?, in sortedEpisodes: [BaseItemDto]) -> BaseItemDto? {
        guard let currentItem else {
            return sortedEpisodes.first { $0.userData?.isPlayed != true }
        }

        if let currentIndex = sortedEpisodes.firstIndex(where: { $0.id == currentItem.id }) {
            return sortedEpisodes
                .dropFirst(currentIndex + 1)
                .first { $0.userData?.isPlayed != true }
        }

        return sortedEpisodes.first {
            $0.userData?.isPlayed != true && episodePlaybackOrder(currentItem, $0)
        }
    }

    private func shouldPreferLatestChangedEpisode(_ latestChanged: BaseItemDto, over currentItem: BaseItemDto) -> Bool {
        guard latestChanged.id != currentItem.id else { return false }
        return !episodePlaybackOrder(latestChanged, currentItem)
    }

    @MainActor
    private func refreshSeason(for item: BaseItemDto?) {
        let seasonViewModel: SeasonItemViewModel?
        if let seasonID = item?.seasonID {
            seasonViewModel = seasons.first(where: { $0.id == seasonID }) ?? seasons.first
        } else {
            seasonViewModel = seasons.first
        }

        seasonViewModel?.send(.refresh)
    }

    private func episodePlaybackOrder(_ lhs: BaseItemDto, _ rhs: BaseItemDto) -> Bool {
        if let lhsID = lhs.id, let rhsID = rhs.id, lhsID == rhsID {
            return false
        }

        let lhsSeason = lhs.parentIndexNumber ?? Int.min
        let rhsSeason = rhs.parentIndexNumber ?? Int.min
        guard lhsSeason == rhsSeason else {
            return lhsSeason < rhsSeason
        }

        let lhsEpisode = lhs.indexNumber ?? Int.min
        let rhsEpisode = rhs.indexNumber ?? Int.min
        guard lhsEpisode == rhsEpisode else {
            return lhsEpisode < rhsEpisode
        }

        return (lhs.sortName ?? lhs.name ?? "") < (rhs.sortName ?? rhs.name ?? "")
    }

    // MARK: - Get First Item Seasons

    private func getSeasons() async throws -> [BaseItemDto] {

        var parameters = EmbyPortSeasonsParameters()
        parameters.isMissing = Defaults[.Customization.shouldShowMissingSeasons] ? nil : false

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.seasons(
            seriesID: item.id!,
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return HomeItemUserDataOverrideStore.applyingOverrides(
            to: response.items ?? [],
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func applyingUserDataOverrides(to item: BaseItemDto) -> BaseItemDto {
        HomeItemUserDataOverrideStore.applyingOverrides(
            to: item,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func applyingUserDataOverrides(to items: [BaseItemDto]) -> [BaseItemDto] {
        HomeItemUserDataOverrideStore.applyingOverrides(
            to: items,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func applyingEpisodeUserDataOverrides(to item: BaseItemDto) -> BaseItemDto {
        HomeItemUserDataOverrideStore.applyingItemOnlyOverride(
            to: item,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func applyingEpisodeUserDataOverrides(to items: [BaseItemDto]) -> [BaseItemDto] {
        HomeItemUserDataOverrideStore.applyingItemOnlyOverrides(
            to: items,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }
}
