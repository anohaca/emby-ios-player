//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct FavoritesView: View {

    var body: some View {
        PagingLibraryView(
            viewModel: ItemLibraryViewModel(
                title: L10n.favorites,
                id: "favorites",
                filters: .favorites
            ),
            showsFilterControls: false
        )
    }
}
