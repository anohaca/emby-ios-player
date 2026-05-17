//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension EmbyCulture: Displayable {

    var displayTitle: String {
        if let twoLetterISOLanguageName,
           let name = Locale.current.localizedString(forLanguageCode: twoLetterISOLanguageName)
        {
            return name
        }

        if let threeLetterISOLanguageNames, let displayName = threeLetterISOLanguageNames
            .compactMap({ Locale.current.localizedString(forLanguageCode: $0) })
            .first
        {
            return displayName
        }

        return displayName ?? L10n.unknown
    }
}

extension EmbyCulture: Identifiable {
    var id: Int {
        hashValue
    }
}
