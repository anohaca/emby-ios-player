//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

// Since we don't view care to view seasons directly, this doesn't subclass from `ItemViewModel`.
// If we ever care for viewing seasons directly, subclass from that and have the library view model
// as a property.
final class SeasonItemViewModel: PagingLibraryViewModel<BaseItemDto>, Identifiable {

    let season: BaseItemDto
    private let seriesID: String?

    var id: String? {
        season.id
    }

    init(season: BaseItemDto, seriesID: String? = nil) {
        self.season = season
        self.seriesID = seriesID ?? season.seriesID ?? season.parentID
        super.init(parent: season)
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

        let items = response.items ?? []

        return items
    }
}
