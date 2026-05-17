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

            // The /Persons endpoint cannot honor item filters like Tags or Years.
            if searchFilters.hasQueryableFilters == false {
                group.addTask {
                    let items = try await self._getPeople(query: query)
                    return (BaseItemKind.person, items)
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
        self.allItems = resolvedAllResults.items
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
        parameters.sortBy = filters.sortBy
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

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let responseItems = response.items ?? []
        logger.info(
            """
            Search all results: query='\(query)' returned=\(responseItems.count) total=\(response.totalRecordCount ?? -1) startIndex=\(response.startIndex ?? -1)
            """
        )

        return (responseItems, response.totalRecordCount)
    }

    private func _getItems(query: String, itemType: BaseItemKind, filters: ItemFilterCollection) async throws -> [BaseItemDto] {
        if itemType == .series, query.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
            return try await SearchSeriesResolver(
                userSession: userSession,
                filters: filters
            )
            .search(query: query, limit: 50)
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

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items ?? []
    }

    private func _getPeople(query: String) async throws -> [BaseItemDto] {

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
        parameters.limit = 10
        parameters.sortBy = [ItemSortBy.random]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        self.suggestions = response.items ?? []
    }
}
