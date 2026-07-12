//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension ItemView {

    struct ContainingCollectionsHStack: View {

        @Default(.Customization.similarPosterType)
        private var posterType

        @Router
        private var router

        let items: [BaseItemDto]

        var body: some View {
            PosterHStack(
                title: "所属合集",
                type: posterType,
                items: items
            ) { item, namespace in
                router.route(to: .item(item: item), in: namespace)
            }
        }
    }
}
