//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Displayable, Storable {

    case system
    case dark
    case light

    static var allCases: [AppAppearance] {
        [.dark]
    }

    var displayTitle: String {
        switch self {
        case .system, .dark, .light:
            L10n.dark
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system, .dark, .light:
            .dark
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system, .dark, .light:
            .dark
        }
    }
}
