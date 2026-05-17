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

    // MARK: - Task

    private var seriesItemTask: AnyCancellable?

    // MARK: - Init

    @MainActor
    override init(item: BaseItemDto) {
        self.seedEpisode = nil
        super.init(item: item)
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
                    async let firstAvailable = getFirstAvailableItem()
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
                        self.ensureSeedSeason(refresh: true)
                        self.refreshSeasonIfNeeded(for: self.seedEpisode ?? self.playButtonItem)
                    }

                    if let episodeItem = try await [nextUp, resume].compacted().first {
                        await MainActor.run {
                            self.playButtonItem = episodeItem
                            self.refreshSeasonIfNeeded(for: episodeItem)
                        }
                    } else if let firstAvailable = try await firstAvailable {
                        await MainActor.run {
                            self.playButtonItem = firstAvailable
                            self.refreshSeasonIfNeeded(for: firstAvailable)
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

    // MARK: - Get Next Up Item

    private func getNextUp() async throws -> BaseItemDto? {

        var parameters = EmbyPortNextUpParameters()
        parameters.fields = .MinimumFields
        parameters.seriesID = item.id

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.nextUp(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        guard let item = response.items?.first, !item.isMissing else {
            return nil
        }

        return item
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

        return response.items?.first
    }

    // MARK: - Get First Available Item

    private func getFirstAvailableItem() async throws -> BaseItemDto? {

        var parameters = EmbyPortItemsParameters()
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortOrder = [.ascending]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items?.first
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

        return response.items ?? []
    }
}
