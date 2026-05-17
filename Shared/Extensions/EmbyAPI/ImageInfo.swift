//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension ImageInfo: @retroactive Identifiable {

    public var id: Int {
        hashValue
    }
}

extension ImageInfo {

    func itemImageSource(itemID: String, client: EmbyPortSessionClient) -> ImageSource {
        let itemImageURL = client.itemImageURL(
            itemID: itemID,
            imageType: imageType?.rawValue ?? "",
            imageIndex: imageIndex,
            tag: imageTag
        )

        return ImageSource(url: itemImageURL)
    }
}
