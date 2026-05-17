//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import Foundation

extension EmbyLogFile {

    var url: URL? {
        guard let name, let client = Container.shared.currentUserSession()?.embyClient else { return nil }
        return client.logFileURL(name: name)
    }

    var type: ServerLogType {
        name.map(ServerLogType.init(rawValue:)) ?? .other
    }
}
