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
final class FilterViewModel: ViewModel {

    @CasePathable
    enum Action {
        case cancel
        case getQueryFilters
        case reset(filterType: ItemFilterType?)

        var transition: Transition {
            switch self {
            case .cancel, .reset: .none
            case .getQueryFilters:
                .background(.retrievingQueryFilters)
            }
        }
    }

    enum BackgroundState {
        case retrievingQueryFilters
    }

    @Published
    private(set) var allFilters: ItemFilterCollection = .all
    @Published
    var currentFilters: ItemFilterCollection

    private let parent: (any LibraryParent)?

    init(
        parent: (any LibraryParent)? = nil,
        currentFilters: ItemFilterCollection = .default
    ) {
        self.parent = parent
        self.currentFilters = currentFilters

        super.init()
    }

    func isFilterSelected(type: ItemFilterType) -> Bool {
        type.group
            .map(\.keyPath)
            .contains { keyPath in
                currentFilters[keyPath: keyPath] != ItemFilterCollection.default[keyPath: keyPath]
            }
    }

    @Function(\Action.Cases.reset)
    private func resetCurrentFilters(_ type: ItemFilterType?) {

        guard let type else {
            currentFilters = .default
            return
        }

        switch type {
        case .genres:
            currentFilters.genres = ItemFilterCollection.default.genres
        case .letter:
            currentFilters.letter = ItemFilterCollection.default.letter
        case .sortBy:
            currentFilters.sortBy = ItemFilterCollection.default.sortBy
            currentFilters.sortOrder = ItemFilterCollection.default.sortOrder
        case .studios:
            currentFilters.studios = ItemFilterCollection.default.studios
        case .tags:
            currentFilters.tags = ItemFilterCollection.default.tags
        case .traits:
            currentFilters.traits = ItemFilterCollection.default.traits
        case .years:
            currentFilters.years = ItemFilterCollection.default.years
        }
    }

    @Function(\Action.Cases.getQueryFilters)
    private func _getQueryFilters() async throws {

        let parameters = EmbyPortQueryFiltersParameters(
            parentID: parent?.id,
            userID: userSession.user.id
        )

        let response = try await userSession.embyClient.queryFilterChoices(parameters)

        let genres: [ItemGenre] = (response.genres ?? [])
            .map(ItemGenre.init)

        let tags = (response.tags ?? [])
            .map(ItemTag.init)

        let studios = (response.studios ?? [])
            .map(ItemStudio.init)
            .filter { !$0.value.isEmpty }

        // Manually sort so that most recent years are "first"
        let years = (response.years ?? [])
            .sorted(by: >)
            .map(ItemYear.init)

        allFilters.genres = genres
        allFilters.studios = studios
        allFilters.tags = tags
        allFilters.years = years
    }
}
