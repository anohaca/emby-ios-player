//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import OrderedCollections
import SwiftUI

@MainActor
@Stateful
final class SearchViewModel: ViewModel {

    @CasePathable
    enum Action {
        case getSuggestions
        case search(query: String)
        case actuallySearch(query: String)

        var transition: Transition {
            switch self {
            case .getSuggestions:
                .none
            case let .search(query):
                query.isEmpty ? .to(.initial) : .to(.searching)
            case .actuallySearch:
                .to(.searching, then: .initial)
                    .onRepeat(.cancel)
            }
        }
    }

    enum State {
        case error
        case initial
        case searching
    }

    @Published
    private(set) var items: [BaseItemKind: [BaseItemDto]] = [:]
    @Published
    private(set) var allItems: [BaseItemDto] = []
    @Published
    private(set) var allResultCount: Int?
    @Published
    private(set) var suggestions: [BaseItemDto] = []

    private var searchQuery: CurrentValueSubject<String, Never> = .init("")

    let filterViewModel: FilterViewModel

    private let retrievingItemTypes: [BaseItemKind] = [
        .audio,
        .boxSet,
        .episode,
        .movie,
        .musicAlbum,
        .musicArtist,
        .musicVideo,
        .liveTvProgram,
        .playlist,
        .series,
        .tvChannel,
        .video,
    ]

    var hasNoResults: Bool {
        allItems.isEmpty && items.values.allSatisfy(\.isEmpty)
    }

    var canSearch: Bool {
        searchQuery.value.isNotEmpty || filterViewModel.currentFilters.hasQueryableFilters
    }

    // MARK: init

    @MainActor
    init(filterViewModel: FilterViewModel) {
        self.filterViewModel = filterViewModel
        super.init()

        searchQuery
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }

                actuallySearch(query: query)
            }
            .store(in: &cancellables)

        filterViewModel.$currentFilters
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                actuallySearch(query: searchQuery.value)
            }
            .store(in: &cancellables)
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        searchQuery.value = query

        await cancel()
    }

    @Function(\Action.Cases.actuallySearch)
    private func _actuallySearch(_ query: String) async throws {

        guard self.canSearch else {
            allItems.removeAll()
            allResultCount = nil
            items.removeAll()
            return
        }

        let searchFilters = filterViewModel.currentFilters.filtersForSearchText(query)

        async let allResults = _getAllItems(query: query, filters: searchFilters)

        let newItems = try await withThrowingTaskGroup(
            of: (BaseItemKind, [BaseItemDto]).self,
            returning: [BaseItemKind: [BaseItemDto]].self
        ) { group in

            for type in retrievingItemTypes {
                group.addTask {
                    let items = try await self._getItems(query: query, itemType: type, filters: searchFilters)
                    return (type, items)
                }
            }

            var result: [BaseItemKind: [BaseItemDto]] = [:]

            while let items = try await group.next() {
                if items.1.isNotEmpty {
                    result[items.0] = items.1
                }
            }

            return result
        }

        let resolvedAllResults = try await allResults

        guard !Task.isCancelled else { return }
        self.allItems = await addingChildImageFallbacks(to: resolvedAllResults.items)
        self.allResultCount = resolvedAllResults.totalRecordCount
        self.items = newItems
    }

    private func _getAllItems(query: String, filters: ItemFilterCollection) async throws -> (items: [BaseItemDto], totalRecordCount: Int?) {
        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.isRecursive = true
        parameters.limit = 50
        parameters.searchTerm = query

        // Filters
        parameters.filters = filters.traits
        parameters.genres = filters.genres.map(\.value)
        parameters.sortBy = filters.embyServerSortBy
        parameters.sortOrder = filters.sortOrder
        parameters.studioIDs = filters.studios.map(\.value)
        parameters.tags = filters.tags.map(\.value)
        parameters.years = filters.years.compactMap { Int($0.value) }

        if filters.letter.first?.value == "#" {
            parameters.nameLessThan = "A"
        } else {
            parameters.nameStartsWith = filters.letter
                .map(\.value)
                .filter { $0 != "#" }
                .first
        }

        let responseItems = try await getVisibleLibraryItems(parameters: parameters)
        logger.info(
            """
            Search all results: query='\(query)' returned=\(responseItems.count)
            """
        )

        return (responseItems, responseItems.count)
    }

    private func _getItems(query: String, itemType: BaseItemKind, filters: ItemFilterCollection) async throws -> [BaseItemDto] {
        if itemType == .series, query.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
            let results = try await SearchSeriesResolver(
                userSession: userSession,
                filters: filters
            )
            .search(query: query, limit: 50)

            return await addingChildImageFallbacks(
                to: results.sortedByVideoBitRateIfNeeded(filters: filters)
            )
        }

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [itemType]
        parameters.isRecursive = true
        parameters.limit = 50
        parameters.searchTerm = query

        // Filters
        parameters.apply(filters: filters)

        let items = try await getVisibleLibraryItems(parameters: parameters)
            .sortedByVideoBitRateIfNeeded(filters: filters)
        return await addingChildImageFallbacks(to: items)
    }

    private func _getPeople(query: String) async throws -> [BaseItemDto] {

        // Emby's Persons endpoint has no parent-library filter.
        guard !SearchLibraryScope.hasHiddenLibraries else { return [] }

        var parameters = EmbyPortPersonsParameters()
        parameters.limit = 20
        parameters.searchTerm = query

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.persons(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items ?? []
    }

    // MARK: suggestions

    @Function(\Action.Cases.getSuggestions)
    private func _getSuggestions() async throws {

        await filterViewModel.getQueryFilters()

        var parameters = EmbyPortItemsParameters()
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 9
        parameters.sortBy = [ItemSortBy.random]

        let suggestionLimit = parameters.limit ?? 10
        let items = Array(
            try await getVisibleLibraryItems(parameters: parameters)
                .filter { $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty }
                .prefix(suggestionLimit)
        )
        self.suggestions = await addingChildImageFallbacks(to: items)
    }

    private func getVisibleLibraryItems(parameters: EmbyPortItemsParameters) async throws -> [BaseItemDto] {
        guard let parentIDs = try await SearchLibraryScope.visibleParentIDs(userSession: userSession) else {
            let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
                parameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )
            return response.items ?? []
        }

        guard parentIDs.isNotEmpty else { return [] }

        return try await withThrowingTaskGroup(of: [BaseItemDto].self) { group in
            for parentID in parentIDs {
                group.addTask {
                    var scopedParameters = parameters
                    scopedParameters.parentID = parentID
                    let response: EmbyPortItemsResponse<BaseItemDto> = try await self.userSession.embyClient.items(
                        scopedParameters,
                        as: EmbyPortItemsResponse<BaseItemDto>.self
                    )
                    return response.items ?? []
                }
            }

            var items: [BaseItemDto] = []
            for try await scopedItems in group {
                items.append(contentsOf: scopedItems)
            }
            return SearchLibraryScope.unique(items)
        }
    }

    private func addingChildImageFallbacks(to items: [BaseItemDto]) async -> [BaseItemDto] {
        let items = await hydratingEpisodeSeriesImages(in: items)

        return await withTaskGroup(of: (Int, BaseItemDto).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard item.needsSearchChildImageFallback,
                          let fallback = try? await self.firstChildImageFallback(for: item) else {
                        return (index, item)
                    }
                    return (index, fallback)
                }
            }

            var resolved = Array<BaseItemDto?>(repeating: nil, count: items.count)
            for await (index, item) in group {
                resolved[index] = item
            }
            return resolved.compactMap { $0 }
        }
    }

    private func hydratingEpisodeSeriesImages(in items: [BaseItemDto]) async -> [BaseItemDto] {
        let seriesIDs: [String] = Array(Set(items.compactMap { item -> String? in
            guard item.type == .episode,
                  item.seriesPrimaryImageTag == nil else { return nil }
            return item.seriesID
        }))
        guard seriesIDs.isNotEmpty else { return items }

        var parameters = EmbyPortItemsParameters()
        parameters.fields = .MinimumFields
        parameters.ids = seriesIDs
        parameters.includeItemTypes = [.series]

        guard let response: EmbyPortItemsResponse<BaseItemDto> = try? await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        ) else {
            return items
        }

        let imageTagsBySeriesID = Dictionary(
            uniqueKeysWithValues: (response.items ?? []).compactMap { series -> (String, String)? in
                guard let id = series.id,
                      let tag = series.imageTags?[ImageType.primary.rawValue] else { return nil }
                return (id, tag)
            }
        )

        return items.map { item in
            guard item.type == .episode,
                  let seriesID = item.seriesID,
                  let imageTag = imageTagsBySeriesID[seriesID] else { return item }

            var hydratedItem = item
            hydratedItem.seriesPrimaryImageTag = imageTag
            return hydratedItem
        }
    }

    private func firstChildImageFallback(for item: BaseItemDto) async throws -> BaseItemDto? {
        guard let itemID = item.id else { return nil }

        var parameters = EmbyPortItemsParameters()
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode, .movie, .series, .video]
        parameters.isRecursive = true
        parameters.limit = 10
        parameters.parentID = itemID
        parameters.sortBy = [.parentIndexNumber, .indexNumber, .dateCreated]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        guard let child = response.items?.first(where: { $0.imageTags?[ImageType.primary.rawValue] != nil }),
              let childID = child.id,
              let imageTag = child.imageTags?[ImageType.primary.rawValue] else {
            return nil
        }

        return item
            .mutating(\.parentPrimaryImageItemID, with: childID)
            .mutating(\.parentPrimaryImageTag, with: imageTag)
    }
}

private extension BaseItemDto {

    var needsSearchChildImageFallback: Bool {
        guard type == .folder || type == .series else { return false }

        return imageTags?.isEmpty != false &&
            backdropImageTags?.isEmpty != false &&
            screenshotImageTags?.isEmpty != false
    }
}
