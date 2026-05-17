//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct EmbyCulture: Codable, Hashable {
    var name: String?
    var displayName: String?
    var twoLetterISOLanguageName: String?
    var threeLetterISOLanguageName: String?
    var threeLetterISOLanguageNames: [String]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case displayName = "DisplayName"
        case twoLetterISOLanguageName = "TwoLetterISOLanguageName"
        case threeLetterISOLanguageName = "ThreeLetterISOLanguageName"
        case threeLetterISOLanguageNames = "ThreeLetterISOLanguageNames"
    }
}

struct EmbyCountry: Codable, Hashable {
    var name: String?
    var displayName: String?
    var twoLetterISORegionName: String?
    var threeLetterISORegionName: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case displayName = "DisplayName"
        case twoLetterISORegionName = "TwoLetterISORegionName"
        case threeLetterISORegionName = "ThreeLetterISORegionName"
    }
}

struct EmbyParentalRating: Codable, Hashable {
    var name: String?
    var value: Int?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case value = "Value"
    }
}
