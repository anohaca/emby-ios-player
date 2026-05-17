//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

final class LatestInLibraryViewModel: PagingLibraryViewModel<BaseItemDto>, Identifiable {

    init(parent: (any LibraryParent)? = nil, pageSize: Int = 50) {
        super.init(parent: parent, filters: .recent, pageSize: pageSize)
    }

    override func get(page: Int) async throws -> [BaseItemDto] {
        if usesFilteredItemsQuery {
            let parameters = itemParameters(for: page)
            let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
                parameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            return await addingChildImageFallbacks(to: response.items ?? [])
        }

        let cumulativeLimit = (page + 1) * pageSize
        let pageStart = page * pageSize

        var unplayedParameters = parameters(limit: cumulativeLimit)
        unplayedParameters.isPlayed = false

        var playedParameters = parameters(limit: cumulativeLimit)
        playedParameters.isPlayed = true

        async let unplayedResponse: [BaseItemDto] = userSession.embyClient.latestItems(
            unplayedParameters,
            as: [BaseItemDto].self
        )
        async let playedResponse: [BaseItemDto] = userSession.embyClient.latestItems(
            playedParameters,
            as: [BaseItemDto].self
        )

        let mergedItems = mergedLatestItems(
            unplayed: try await unplayedResponse,
            played: try await playedResponse,
            limit: cumulativeLimit
        )

        guard pageStart < mergedItems.count else { return [] }

        return await addingChildImageFallbacks(to: Array(mergedItems.dropFirst(pageStart).prefix(pageSize)))
    }

    override func getRandomItem() async -> BaseItemDto? {
        var parameters = itemParameters(for: nil)
        parameters.limit = 1
        parameters.sortBy = [ItemSortBy.random]

        let response: EmbyPortItemsResponse<BaseItemDto>? = try? await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response?.items?.first
    }

    private func parameters(limit: Int) -> EmbyPortLatestMediaParameters {

        var parameters = EmbyPortLatestMediaParameters()
        parameters.parentID = parent?.id
        parameters.fields = .MinimumFields
        parameters.enableUserData = true
        parameters.limit = limit

        return parameters
    }

    private var usesFilteredItemsQuery: Bool {
        filterViewModel?.currentFilters != .recent
    }

    private func itemParameters(for page: Int?) -> EmbyPortItemsParameters {
        var parameters = EmbyPortItemsParameters()

        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = BaseItemKind.supportedCases
        parameters.isRecursive = (parent as? BaseItemDto)?.isRecursiveCollection ?? true
        parameters.sortBy = [ItemSortBy.dateCreated]
        parameters.sortOrder = [.descending]

        if let parent {
            parameters = parent.setParentParameters(parameters)
        }

        if let page {
            parameters.limit = pageSize
            parameters.startIndex = page * pageSize
        }

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

            if filters.sortBy.first == .random {
                parameters.excludeItemIDs = elements.compactMap(\.id)
            }
        }

        return parameters
    }

    private func mergedLatestItems(
        unplayed: [BaseItemDto],
        played: [BaseItemDto],
        limit: Int
    ) -> [BaseItemDto] {
        var elements: [BaseItemDto] = []
        var seenIDs: Set<String> = []
        var unplayedIndex = 0
        var playedIndex = 0

        while elements.count < limit, unplayedIndex < unplayed.count || playedIndex < played.count {
            if unplayedIndex < unplayed.count {
                append(unplayed[unplayedIndex], to: &elements, seenIDs: &seenIDs)
                unplayedIndex += 1
            }

            if elements.count >= limit { break }

            if playedIndex < played.count {
                append(played[playedIndex], to: &elements, seenIDs: &seenIDs)
                playedIndex += 1
            }
        }

        return elements
    }

    private func append(
        _ item: BaseItemDto,
        to elements: inout [BaseItemDto],
        seenIDs: inout Set<String>
    ) {
        guard let id = item.id else {
            elements.append(item)
            return
        }

        guard seenIDs.insert(id).inserted else { return }
        elements.append(item)
    }
}
