//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import Foundation
import SwiftUI

extension BaseItemPerson: Poster {

    var preferredPosterDisplayType: PosterDisplayType {
        .portrait
    }

    var unwrappedIDHashOrZero: Int {
        id?.hashValue ?? 0
    }

    var subtitle: String? {
        firstRole
    }

    var systemImage: String {
        "person.fill"
    }

    func portraitImageSources(maxWidth: CGFloat? = nil, quality: Int? = nil) -> [ImageSource] {

        guard let client = Container.shared.currentUserSession()?.embyClient else { return [] }

        // TODO: figure out what to do about screen scaling with .main being deprecated
        //       - maxWidth assume already scaled?
        let scaleWidth: Int? = maxWidth == nil ? nil : UIScreen.main.scale(maxWidth!)
        let imageWidth = scaleWidth ?? maxWidth.map(Int.init)

        let url = client.itemImageURL(
            itemID: id ?? "",
            imageType: ImageType.primary.rawValue,
            maxWidth: imageWidth.map(Double.init),
            quality: quality,
            tag: primaryImageTag
        )
        let blurHash: String? = imageBlurHashes?.primary?[primaryImageTag]

        return [ImageSource(
            url: url,
            blurHash: blurHash
        )]
    }

    func transform(image: Image) -> some View {
        image
    }
}
