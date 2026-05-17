//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct ServerCheckView: View {

    @Router
    private var router

    @StateObject
    private var viewModel = ServerCheckViewModel()

    var body: some View {
        ZStack {
            EmbyAppBackgroundView()

            switch viewModel.state {
            case .initial:
                ZStack {
                    ProgressView()
                }
            case .error:
                viewModel.error.map {
                    ErrorView(error: $0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
        .refreshable {
            viewModel.checkServer()
        }
        .onFirstAppear {
            viewModel.checkServer()
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case .connected:
                router.root(.mainTab)
            }
        }
        .topBarTrailing {

            SettingsBarButton(
                server: viewModel.userSession.server,
                user: viewModel.userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }
}
