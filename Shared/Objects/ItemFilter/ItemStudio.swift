//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct ItemStudio: Codable, Hashable, ItemFilter {

    let id: String
    let name: String

    var displayTitle: String {
        name
    }

    var value: String {
        id
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ studio: NameGuidPair) {
        self.id = studio.id ?? studio.name ?? ""
        self.name = studio.name ?? studio.id ?? .emptyDash
    }

    init(from anyFilter: AnyItemFilter) {
        self.id = anyFilter.value
        self.name = anyFilter.displayTitle
    }
}
