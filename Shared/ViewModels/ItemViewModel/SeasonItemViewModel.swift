//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import IdentifiedCollections

// Since we don't view care to view seasons directly, this doesn't subclass from `ItemViewModel`.
// If we ever care for viewing seasons directly, subclass from that and have the library view model
// as a property.
final class SeasonItemViewModel: PagingLibraryViewModel<BaseItemDto>, Identifiable {

    let season: BaseItemDto
    @Published
    private(set) var userDataDisplayRevision = 0

    private let seriesID: String?

    var id: String? {
        season.id
    }

    init(season: BaseItemDto, seriesID: String? = nil) {
        self.season = season
        self.seriesID = seriesID ?? season.seriesID ?? season.parentID
        super.init(parent: season)

        observeUserDataOverrideChanges()
    }

    override func get(page: Int) async throws -> [BaseItemDto] {
        guard let seriesID else { throw ErrorMessage("Expected series ID missing") }
        guard let seasonID = season.id else { throw ErrorMessage("Expected season ID missing") }

        var parameters = EmbyPortEpisodesParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.isMissing = Defaults[.Customization.shouldShowMissingEpisodes] ? nil : false
        parameters.seasonID = seasonID

//        parameters.startIndex = page * pageSize
//        parameters.limit = pageSize

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.episodes(
            seriesID: seriesID,
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return applyingUserDataOverrides(to: response.items ?? [])
    }

    private func observeUserDataOverrideChanges() {
        Notifications[.itemShouldRefreshMetadata]
            .publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] itemID in
                guard let self, self.shouldApplyUserDataOverrideChange(for: itemID) else { return }

                self.applyUserDataOverridesToVisibleEpisodes()
            }
            .store(in: &cancellables)
    }

    private func shouldApplyUserDataOverrideChange(for itemID: String) -> Bool {
        itemID == season.id ||
            itemID == seriesID ||
            elements.contains { $0.id == itemID || $0.parentID == itemID || $0.seasonID == itemID || $0.seriesID == itemID }
    }

    private func applyUserDataOverridesToVisibleEpisodes() {
        elements = IdentifiedArray(
            applyingUserDataOverrides(to: Array(elements)),
            id: \.unwrappedIDHashOrZero,
            uniquingIDsWith: { lhs, _ in lhs }
        )
        userDataDisplayRevision += 1
    }

    private func applyingUserDataOverrides(to episodes: [BaseItemDto]) -> [BaseItemDto] {
        guard let userSession else { return episodes }

        return HomeItemUserDataOverrideStore.applyingOverrides(
            to: episodes.map(episodeWithKnownRelationships),
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    private func episodeWithKnownRelationships(_ episode: BaseItemDto) -> BaseItemDto {
        var copy = episode

        if copy.seriesID == nil {
            copy.seriesID = seriesID
        }

        if copy.seasonID == nil {
            copy.seasonID = season.id
        }

        return copy
    }
}
