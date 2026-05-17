//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

/// A structure representing a collection of item filters
struct ItemFilterCollection: Hashable, Storable {

    var genres: [ItemGenre] = []
    var itemTypes: [BaseItemKind] = []
    var letter: [ItemLetter] = []
    var sortBy: [ItemSortBy] = [ItemSortBy.sortName]
    var sortOrder: [ItemSortOrder] = [ItemSortOrder.ascending]
    var studios: [ItemStudio] = []
    var tags: [ItemTag] = []
    var traits: [ItemTrait] = []
    var years: [ItemYear] = []

    enum CodingKeys: String, CodingKey {
        case genres
        case itemTypes
        case letter
        case sortBy
        case sortOrder
        case studios
        case tags
        case traits
        case years
    }

    init(
        genres: [ItemGenre] = [],
        itemTypes: [BaseItemKind] = [],
        letter: [ItemLetter] = [],
        sortBy: [ItemSortBy] = [ItemSortBy.sortName],
        sortOrder: [ItemSortOrder] = [ItemSortOrder.ascending],
        studios: [ItemStudio] = [],
        tags: [ItemTag] = [],
        traits: [ItemTrait] = [],
        years: [ItemYear] = []
    ) {
        self.genres = genres
        self.itemTypes = itemTypes
        self.letter = letter
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.studios = studios
        self.tags = tags
        self.traits = traits
        self.years = years
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        genres = try container.decodeIfPresent([ItemGenre].self, forKey: .genres) ?? []
        itemTypes = try container.decodeIfPresent([BaseItemKind].self, forKey: .itemTypes) ?? []
        letter = try container.decodeIfPresent([ItemLetter].self, forKey: .letter) ?? []
        sortBy = try container.decodeIfPresent([ItemSortBy].self, forKey: .sortBy) ?? [ItemSortBy.sortName]
        sortOrder = try container.decodeIfPresent([ItemSortOrder].self, forKey: .sortOrder) ?? [ItemSortOrder.ascending]
        studios = try container.decodeIfPresent([ItemStudio].self, forKey: .studios) ?? []
        tags = try container.decodeIfPresent([ItemTag].self, forKey: .tags) ?? []
        traits = try container.decodeIfPresent([ItemTrait].self, forKey: .traits) ?? []
        years = try container.decodeIfPresent([ItemYear].self, forKey: .years) ?? []
    }

    /// The default collection of filters
    static let `default`: ItemFilterCollection = .init()

    static let favorites: ItemFilterCollection = .init(
        traits: [ItemTrait.isFavorite]
    )
    static let recent: ItemFilterCollection = .init(
        sortBy: [ItemSortBy.dateCreated],
        sortOrder: [ItemSortOrder.descending]
    )

    /// A collection that has all statically available values.
    ///
    /// These may be altered when used to better represent all
    /// available values within the current context.
    static let all: ItemFilterCollection = .init(
        letter: ItemLetter.allCases,
        sortBy: ItemSortBy.supportedCases,
        sortOrder: ItemSortOrder.allCases,
        traits: ItemTrait.supportedCases
    )

    var isNotEmpty: Bool {
        self != Self.default
    }

    var hasQueryableFilters: Bool {
        genres.isNotEmpty || itemTypes.isNotEmpty || letter.isNotEmpty || studios.isNotEmpty || tags.isNotEmpty || traits.isNotEmpty || years.isNotEmpty
    }

    var searchSectionFilters: ItemFilterCollection {
        ItemFilterCollection(sortBy: sortBy, sortOrder: sortOrder)
    }

    func filtersForSearchText(_ query: String) -> ItemFilterCollection {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? self : searchSectionFilters
    }
}
