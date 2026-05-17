//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct RemoteSubtitleInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String? = nil
    var name: String? = nil
    var threeLetterISOLanguageName: String? = nil
    var downloadCount: Int? = nil
    var communityRating: Double? = nil
    var author: String? = nil
    var format: String? = nil

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case threeLetterISOLanguageName = "ThreeLetterISOLanguageName"
        case downloadCount = "DownloadCount"
        case communityRating = "CommunityRating"
        case author = "Author"
        case format = "Format"
    }
}

struct UploadSubtitleDto: Encodable, Hashable, Sendable {
    var data: String
    var format: String
    var isForced: Bool
    var isHearingImpaired: Bool
    var language: String

    enum CodingKeys: String, CodingKey {
        case data = "Data"
        case format = "Format"
        case isForced = "IsForced"
        case isHearingImpaired = "IsHearingImpaired"
        case language = "Language"
    }
}
