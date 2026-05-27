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
        guard let userSession else { return [] }

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
        let response = try await latestItems(limit: cumulativeLimit)

        guard pageStart < response.count else { return [] }

        return await addingChildImageFallbacks(to: Array(response.dropFirst(pageStart).prefix(pageSize)))
    }

    private func latestItems(limit: Int) async throws -> [BaseItemDto] {
        guard let userSession else { return [] }

        let response: [BaseItemDto] = try await userSession.embyClient.latestItems(
            parameters(limit: limit * 3),
            as: [BaseItemDto].self
        )

        return mergedLatestItems(items: response, limit: limit)
    }

    override func getRandomItem() async -> BaseItemDto? {
        guard let userSession else { return nil }

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
        parameters.fields = .MinimumFields + [.dateCreated, .dateLastMediaAdded]
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

    private func mergedLatestItems(items: [BaseItemDto], limit: Int) -> [BaseItemDto] {
        var elements: [BaseItemDto] = []
        var seenIDs: Set<String> = []

        for item in items {
            guard append(item, to: &elements, seenIDs: &seenIDs) else { continue }
        }

        return elements.prefix(limit).map { $0 }
    }

    private func append(
        _ item: BaseItemDto,
        to elements: inout [BaseItemDto],
        seenIDs: inout Set<String>
    ) -> Bool {
        guard let id = latestDedupeID(for: item) else {
            elements.append(item)
            return true
        }

        guard seenIDs.insert(id).inserted else { return false }
        elements.append(item)
        return true
    }

    private func latestDedupeID(for item: BaseItemDto) -> String? {
        let identity = latestSortIdentity(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if item.type == .series, identity.isNotEmpty {
            return "series:\(identity)"
        }

        return item.id ?? (identity.isEmpty ? nil : identity)
    }

    private func latestSortIdentity(for item: BaseItemDto) -> String {
        item.sortName ?? item.name ?? item.id ?? .emptyDash
    }
}
