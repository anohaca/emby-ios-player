//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

// TODO: verify this properly returns pages of items in correct date-added order
//       *when* new episodes are added to a series?
final class RecentlyAddedLibraryViewModel: PagingLibraryViewModel<BaseItemDto> {

    // Necessary because this is paginated and also used on home view
    init(customPageSize: Int? = nil) {

        // Why doesn't `super.init(title:id:pageSize)` init work?
        let parent = TitledLibraryParent(displayTitle: L10n.recentlyAdded, id: "recentlyAdded")
        if let customPageSize {
            super.init(parent: parent, filters: .recent, pageSize: customPageSize)
        } else {
            super.init(parent: parent, filters: .recent)
        }
    }

    override func get(page: Int) async throws -> [BaseItemDto] {

        let parameters = parameters(for: page)
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return await addingChildImageFallbacks(to: response.items ?? [])
    }

    private func parameters(for page: Int) -> EmbyPortItemsParameters {

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = pageSize
        parameters.sortBy = [ItemSortBy.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.startIndex = 0

        if let filterViewModel {
            let filters = filterViewModel.currentFilters
            parameters.filters = filters.traits
            parameters.genres = filters.genres.map(\.value)
            parameters.sortBy = filters.sortBy
            parameters.sortOrder = filters.sortOrder
            parameters.studioIDs = filters.studios.map(\.value)
            parameters.tags = filters.tags.map(\.value)
            parameters.years = filters.years.compactMap { Int($0.value) }

            if filters.itemTypes.isNotEmpty {
                parameters.includeItemTypes = filters.itemTypes
            }

            if filters.letter.first?.value == "#" {
                parameters.nameLessThan = "A"
            } else {
                parameters.nameStartsWith = filters.letter
                    .map(\.value)
                    .filter { $0 != "#" }
                    .first
            }
        }

        // Necessary to get an actual "next page" with this endpoint.
        // Could be a performance issue for lots of items, but there's
        // nothing we can do about it. Don't apply this on page 0: the
        // home screen refresh is also page 0, and excluding the current
        // rows makes the "recently added" shelf rotate on every refresh.
        if page > 0 {
            parameters.excludeItemIDs = elements.compactMap(\.id)
        }

        return parameters
    }
}
