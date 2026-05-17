//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct EmbyPortRemoteSearchInfo: Codable, Hashable, Sendable {
    var name: String? = nil
    var originalTitle: String? = nil
    var year: Int? = nil

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case year = "Year"
    }
}

struct EmbyPortRemoteSearchQuery<SearchInfo: Encodable & Sendable>: Encodable, Sendable {
    var itemID: String
    var searchInfo: SearchInfo

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case searchInfo = "SearchInfo"
    }
}

typealias BoxSetInfo = EmbyPortRemoteSearchInfo
typealias MovieInfo = EmbyPortRemoteSearchInfo
typealias PersonLookupInfo = EmbyPortRemoteSearchInfo
typealias SeriesInfo = EmbyPortRemoteSearchInfo

typealias BoxSetInfoRemoteSearchQuery = EmbyPortRemoteSearchQuery<BoxSetInfo>
typealias MovieInfoRemoteSearchQuery = EmbyPortRemoteSearchQuery<MovieInfo>
typealias PersonLookupInfoRemoteSearchQuery = EmbyPortRemoteSearchQuery<PersonLookupInfo>
typealias SeriesInfoRemoteSearchQuery = EmbyPortRemoteSearchQuery<SeriesInfo>
