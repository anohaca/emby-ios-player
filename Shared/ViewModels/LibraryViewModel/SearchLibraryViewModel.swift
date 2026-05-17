//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@MainActor
final class SearchLibraryViewModel: PagingLibraryViewModel<BaseItemDto> {

    private let itemType: BaseItemKind?
    private let query: String
    private var expandedSeriesCache: [BaseItemDto]?
    private var expandedSeriesCacheFilters: ItemFilterCollection?

    init(
        title: String,
        id: String?,
        query: String,
        itemType: BaseItemKind?,
        filters: ItemFilterCollection?,
        pageSize: Int = 50
    ) {
        self.itemType = itemType
        self.query = query
        let effectiveFilters = filters?.filtersForSearchText(query)

        super.init(
            parent: TitledLibraryParent(
                displayTitle: title,
                id: id
            ),
            filters: itemType == .person ? nil : effectiveFilters,
            pageSize: pageSize
        )
    }

    override func get(page: Int) async throws -> [BaseItemDto] {
        if itemType == .person {
            return try await getPeople(page: page)
        }

        if itemType == .series, query.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
            let items = try await expandedSeriesResults()
            let startIndex = page * pageSize
            guard startIndex < items.count else { return [] }
            return Array(items.dropFirst(startIndex).prefix(pageSize))
        }

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        if let itemType {
            parameters.includeItemTypes = [itemType]
        }
        parameters.isRecursive = true
        parameters.limit = pageSize
        parameters.searchTerm = query
        parameters.startIndex = page * pageSize

        if let filterViewModel {
            parameters.apply(filters: filterViewModel.currentFilters)
        }

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return await addingChildImageFallbacks(to: response.items ?? [])
    }

    private func getPeople(page: Int) async throws -> [BaseItemDto] {
        var parameters = EmbyPortPersonsParameters()
        parameters.limit = pageSize
        parameters.searchTerm = query
        parameters.startIndex = page * pageSize

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.persons(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items ?? []
    }

    private func expandedSeriesResults() async throws -> [BaseItemDto] {
        let currentFilters = filterViewModel?.currentFilters

        if let expandedSeriesCache,
           expandedSeriesCacheFilters == currentFilters
        {
            return expandedSeriesCache
        }

        let results = try await SearchSeriesResolver(
            userSession: userSession,
            filters: currentFilters
        )
        .search(query: query)

        expandedSeriesCache = results
        expandedSeriesCacheFilters = currentFilters

        return results
    }
}

struct SearchSeriesResolver {

    private let userSession: UserSession
    private let filters: ItemFilterCollection?

    private let pageSize = 200
    private let maxScannedItems = 1000

    init(
        userSession: UserSession,
        filters: ItemFilterCollection?
    ) {
        self.userSession = userSession
        self.filters = filters
    }

    func search(query: String, limit: Int? = nil) async throws -> [BaseItemDto] {
        let series = try await matchingItems(
            query: query,
            itemTypes: [.series],
            maxItems: limit ?? maxScannedItems
        )

        return Array(series.prefix(limit ?? series.count))
    }

    private func matchingItems(
        query: String,
        itemTypes: [BaseItemKind],
        maxItems: Int
    ) async throws -> [BaseItemDto] {
        var items: [BaseItemDto] = []
        items.reserveCapacity(min(maxItems, pageSize))

        var startIndex = 0

        while items.count < maxItems {
            let requestLimit = min(pageSize, maxItems - items.count)
            var parameters = EmbyPortItemsParameters()
            parameters.enableUserData = true
            parameters.fields = .MinimumFields
            parameters.includeItemTypes = itemTypes
            parameters.isRecursive = true
            parameters.limit = requestLimit
            parameters.searchTerm = query
            parameters.startIndex = startIndex

            if let filters {
                parameters.apply(filters: filters)
            }

            let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
                parameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            let pageItems = response.items ?? []
            items.append(contentsOf: pageItems)

            guard pageItems.count == requestLimit else { break }
            startIndex += requestLimit
        }

        return items
    }

}

extension EmbyPortItemsParameters {

    mutating func apply(filters: ItemFilterCollection) {
        self.filters = filters.traits
        genres = filters.genres.map(\.value)
        sortBy = filters.sortBy
        sortOrder = filters.sortOrder
        studioIDs = filters.studios.map(\.value)
        tags = filters.tags.map(\.value)
        years = filters.years.compactMap { Int($0.value) }

        if filters.letter.first?.value == "#" {
            nameLessThan = "A"
        } else {
            nameStartsWith = filters.letter
                .map(\.value)
                .filter { $0 != "#" }
                .first
        }
    }
}
