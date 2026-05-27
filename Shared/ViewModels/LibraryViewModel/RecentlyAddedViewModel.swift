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

    private let homeRecentlyUpdated: Bool

    // Necessary because this is paginated and also used on home view
    init(customPageSize: Int? = nil, homeRecentlyUpdated: Bool = false) {
        self.homeRecentlyUpdated = homeRecentlyUpdated

        // Why doesn't `super.init(title:id:pageSize)` init work?
        let parent = TitledLibraryParent(displayTitle: L10n.recentlyAdded, id: "recentlyAdded")
        if let customPageSize {
            super.init(parent: parent, filters: .recent, pageSize: customPageSize)
        } else {
            super.init(parent: parent, filters: .recent)
        }
    }

    override func get(page: Int) async throws -> [BaseItemDto] {
        if homeRecentlyUpdated {
            return try await getRecentlyUpdated(page: page)
        }

        let parameters = parameters(for: page)
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return await addingChildImageFallbacks(to: response.items ?? [])
    }

    private func getRecentlyUpdated(page: Int) async throws -> [BaseItemDto] {
        let cumulativeLimit = (page + 1) * pageSize
        let pageStart = page * pageSize

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            recentlyUpdatedParameters(limit: cumulativeLimit * 3),
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let updatedItems = mergedRecentlyUpdatedItems(
            items: response.items ?? [],
            limit: cumulativeLimit
        )

        guard pageStart < updatedItems.count else { return [] }

        return await addingChildImageFallbacks(to: Array(updatedItems.dropFirst(pageStart).prefix(pageSize)))
    }

    private func recentlyUpdatedParameters(limit: Int) -> EmbyPortItemsParameters {
        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields + [
            .dateCreated,
            .dateLastMediaAdded,
            .parentID,
        ]
        parameters.includeItemTypes = [.episode, .movie, .video]
        parameters.isRecursive = true
        parameters.limit = limit
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.startIndex = 0

        return parameters
    }

    private func parameters(for page: Int) -> EmbyPortItemsParameters {

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields + [.dateCreated, .dateLastMediaAdded]
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

    private func mergedRecentlyUpdatedItems(items: [BaseItemDto], limit: Int) -> [BaseItemDto] {
        var elements: [BaseItemDto] = []
        var seenIDs: Set<String> = []

        for item in items.map(homeRecentlyUpdatedItem(for:)) {
            guard let id = recentlyUpdatedDedupeID(for: item) else {
                elements.append(item)
                continue
            }

            guard seenIDs.insert(id).inserted else { continue }
            elements.append(item)
        }

        return elements
            .sorted(by: recentlyUpdatedPrecedes(_:_:))
            .prefix(limit)
            .map { $0 }
    }

    private func homeRecentlyUpdatedItem(for item: BaseItemDto) -> BaseItemDto {
        guard item.type == .episode,
              let seriesID = item.seriesID
        else {
            return item
        }

        var seriesItem = item
        seriesItem.id = seriesID
        seriesItem.name = item.seriesName ?? item.name
        seriesItem.sortName = item.seriesName ?? item.sortName
        seriesItem.type = .series
        seriesItem.dateLastMediaAdded = item.dateCreated ?? item.dateLastMediaAdded
        seriesItem.dateCreated = item.dateCreated
        seriesItem.imageTags = item.seriesPrimaryImageTag.map { [ImageType.primary.rawValue: $0] }
        seriesItem.parentPrimaryImageItemID = seriesID
        seriesItem.parentPrimaryImageTag = item.seriesPrimaryImageTag

        return seriesItem
    }

    private func recentlyUpdatedDedupeID(for item: BaseItemDto) -> String? {
        let identity = recentlyUpdatedIdentity(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if item.type == .series, identity.isNotEmpty {
            return "series:\(identity)"
        }

        return item.id ?? (identity.isEmpty ? nil : identity)
    }

    private func recentlyUpdatedPrecedes(_ lhs: BaseItemDto, _ rhs: BaseItemDto) -> Bool {
        let lhsDate = recentlyUpdatedDate(for: lhs)
        let rhsDate = recentlyUpdatedDate(for: rhs)

        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return recentlyUpdatedIdentity(for: lhs).localizedStandardCompare(recentlyUpdatedIdentity(for: rhs)) == .orderedAscending
    }

    private func recentlyUpdatedDate(for item: BaseItemDto) -> Date {
        item.dateLastMediaAdded ?? item.dateCreated ?? .distantPast
    }

    private func recentlyUpdatedIdentity(for item: BaseItemDto) -> String {
        item.sortName ?? item.name ?? item.id ?? .emptyDash
    }
}
