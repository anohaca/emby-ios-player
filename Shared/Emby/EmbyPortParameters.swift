//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct EmbyPortItemsParameters {
    var adjacentTo: String?
    var enableUserData: Bool?
    var excludeItemIDs: [String]?
    var fields: [ItemFields]?
    var filters: [EmbyItemTrait]?
    var genres: [String]?
    var ids: [String]?
    var includeItemTypes: [BaseItemKind]?
    var isRecursive: Bool?
    var limit: Int?
    var nameLessThan: String?
    var nameStartsWith: String?
    var parentID: String?
    var personIDs: [String]?
    var searchTerm: String?
    var sortBy: [ItemSortBy]?
    var sortOrder: [SortOrder]?
    var startIndex: Int?
    var studioIDs: [String]?
    var tags: [String]?
    var userID: String?
    var years: [Int]?
}

struct EmbyPortLatestMediaParameters {
    var enableUserData: Bool?
    var fields: [ItemFields]?
    var isPlayed: Bool?
    var limit: Int?
    var parentID: String?
    var userID: String?
}

struct EmbyPortNextUpParameters {
    var enableRewatching: Bool?
    var enableUserData: Bool?
    var fields: [ItemFields]?
    var limit: Int?
    var nextUpDateCutoff: Date?
    var seriesID: String?
    var startIndex: Int?
    var userID: String?
}

struct EmbyPortResumeItemsParameters {
    var fields: [ItemFields]?
    var limit: Int?
    var parentID: String?
    var userID: String?
}

struct EmbyPortEpisodesParameters {
    var adjacentTo: String?
    var enableUserData: Bool?
    var fields: [ItemFields]?
    var isMissing: Bool?
    var limit: Int?
    var seasonID: String?
    var userID: String?
}

struct EmbyPortSeasonsParameters {
    var isMissing: Bool?
    var userID: String?
}

struct EmbyPortPersonsParameters {
    var limit: Int?
    var searchTerm: String?
    var startIndex: Int?
    var userID: String?
}

struct EmbyPortGenresParameters {
    var includeItemTypes: [BaseItemKind]?
    var limit: Int?
    var parentID: String?
    var searchTerm: String?
    var sortBy: [ItemSortBy]?
    var sortOrder: [SortOrder]?
    var startIndex: Int?
    var userID: String?
}

struct EmbyPortStudiosParameters {
    var includeItemTypes: [BaseItemKind]?
    var limit: Int?
    var parentID: String?
    var searchTerm: String?
    var sortBy: [ItemSortBy]?
    var sortOrder: [SortOrder]?
    var startIndex: Int?
    var userID: String?
}

struct EmbyPortLiveTVChannelsParameters {
    var fields: [ItemFields]?
    var limit: Int?
    var sortBy: [ItemSortBy]?
    var startIndex: Int?
    var userID: String?
}

struct EmbyPortLiveTVProgramsParameters {
    var channelIDs: [String]?
    var fields: [ItemFields]?
    var hasAired: Bool?
    var isKids: Bool?
    var isMovie: Bool?
    var isNews: Bool?
    var isSeries: Bool?
    var isSports: Bool?
    var limit: Int?
    var maxStartDate: Date?
    var minEndDate: Date?
    var sortBy: [ItemSortBy]?
    var userID: String?
}

struct EmbyPortRecommendedProgramsParameters {
    var fields: [ItemFields]?
    var isAiring: Bool?
    var limit: Int?
    var userID: String?
}

struct EmbyPortQueryFiltersParameters {
    var parentID: String?
    var userID: String?
}

struct EmbyPortSimilarItemsParameters {
    var fields: [ItemFields]?
    var limit: Int?
    var userID: String?
}

struct EmbyPortRemoteImagesParameters {
    var isIncludeAllLanguages: Bool?
    var limit: Int?
    var providerName: String?
    var startIndex: Int?
    var type: ImageType?
}

struct EmbyPortSessionsParameters {
    var activeWithinSeconds: Int?
}

struct EmbyPortActivityLogParameters {
    var hasUserID: Bool?
    var limit: Int?
    var minDate: Date?
    var startIndex: Int?
}

extension EmbyPortSessionClient {

    func items<Response: Decodable>(
        _ parameters: EmbyPortItemsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await items(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func latestItems<Response: Decodable>(
        _ parameters: EmbyPortLatestMediaParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await latestItems(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func nextUp<Response: Decodable>(
        _ parameters: EmbyPortNextUpParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await nextUp(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func resumeItems<Response: Decodable>(
        _ parameters: EmbyPortResumeItemsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await resumeItems(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func episodes<Response: Decodable>(
        seriesID: String,
        _ parameters: EmbyPortEpisodesParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await episodes(seriesID: seriesID, queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func seasons<Response: Decodable>(
        seriesID: String,
        _ parameters: EmbyPortSeasonsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await seasons(seriesID: seriesID, queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func persons<Response: Decodable>(
        _ parameters: EmbyPortPersonsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await persons(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func genres<Response: Decodable>(
        _ parameters: EmbyPortGenresParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await genres(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func studios<Response: Decodable>(
        _ parameters: EmbyPortStudiosParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await studios(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func liveTVChannels<Response: Decodable>(
        _ parameters: EmbyPortLiveTVChannelsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await liveTVChannels(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func liveTVPrograms<Response: Decodable>(
        _ parameters: EmbyPortLiveTVProgramsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await liveTVPrograms(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func recommendedPrograms<Response: Decodable>(
        _ parameters: EmbyPortRecommendedProgramsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await recommendedPrograms(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func queryFilters<Response: Decodable>(
        _ parameters: EmbyPortQueryFiltersParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await queryFilters(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func queryFilterChoices(_ parameters: EmbyPortQueryFiltersParameters) async throws -> EmbyPortQueryFiltersResponse {
        let queryItems = EmbyPortQueryItemBuilder.queryItems(from: parameters)

        do {
            return try await queryFilters(queryItems: queryItems, as: EmbyPortQueryFiltersResponse.self)
        } catch EmbyPortAPIError.httpStatus(404) {
            return try await embyQueryFilterChoices(queryItems: queryItems)
        }
    }

    func similarItems<Response: Decodable>(
        itemID: String,
        _ parameters: EmbyPortSimilarItemsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await similarItems(itemID: itemID, queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func remoteImages<Response: Decodable>(
        itemID: String,
        _ parameters: EmbyPortRemoteImagesParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await remoteImages(itemID: itemID, queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func sessions<Response: Decodable>(
        _ parameters: EmbyPortSessionsParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await sessions(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    func activityLogEntries<Response: Decodable>(
        _ parameters: EmbyPortActivityLogParameters,
        as type: Response.Type
    ) async throws -> Response {
        try await activityLogEntries(queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters), as: type)
    }

    private func embyQueryFilterChoices(queryItems: [URLQueryItem]) async throws -> EmbyPortQueryFiltersResponse {
        let recursiveQueryItems = addingRecursiveTrue(to: queryItems)

        async let genresResponse: EmbyPortItemsResponse<BaseItemDto> = genres(
            queryItems: recursiveQueryItems,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )
        async let tagsResponse: EmbyPortItemsResponse<BaseItemDto> = tags(
            queryItems: recursiveQueryItems,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )
        async let studiosResponse: EmbyPortItemsResponse<BaseItemDto> = studios(
            queryItems: recursiveQueryItems,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )
        async let yearsResponse: EmbyPortItemsResponse<BaseItemDto> = years(
            queryItems: recursiveQueryItems,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let rawGenreNames = filterNames(from: try await genresResponse)
        let rawTagNames = filterNames(from: try await tagsResponse)
        let studios = filterStudios(from: try await studiosResponse)
        let yearNames = filterNames(from: try await yearsResponse)
        let tagNameSet = Set(rawTagNames.map { $0.lowercased() })
        let studioNameSet = Set(studios.compactMap(\.name).map { $0.lowercased() })
        let genreNames = rawGenreNames
            .filter { !tagNameSet.contains($0.lowercased()) }
            .filter { !studioNameSet.contains($0.lowercased()) }
        let genreNameSet = Set(genreNames.map { $0.lowercased() })
        let tagNames = rawTagNames
            .filter { !genreNameSet.contains($0.lowercased()) }
            .filter { !studioNameSet.contains($0.lowercased()) }

        return EmbyPortQueryFiltersResponse(
            genres: genreNames,
            studios: studios,
            tags: tagNames,
            years: yearNames.compactMap(Int.init)
        )
    }

    private func addingRecursiveTrue(to queryItems: [URLQueryItem]) -> [URLQueryItem] {
        if queryItems.contains(where: { $0.name.caseInsensitiveCompare("Recursive") == .orderedSame }) {
            return queryItems
        }

        return queryItems + [URLQueryItem(name: "Recursive", value: "true")]
    }

    private func filterNames(from response: EmbyPortItemsResponse<BaseItemDto>) -> [String] {
        var seen: Set<String> = []
        return (response.items ?? [])
            .compactMap(\.name)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private func filterStudios(from response: EmbyPortItemsResponse<BaseItemDto>) -> [NameGuidPair] {
        var seen: Set<String> = []
        return (response.items ?? [])
            .compactMap { item -> NameGuidPair? in
                guard let id = item.id, let name = item.name, !id.isEmpty, !name.isEmpty else { return nil }
                let key = id.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return NameGuidPair(id: id, name: name)
            }
    }
}
