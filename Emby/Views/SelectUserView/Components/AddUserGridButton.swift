//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import OrderedCollections
import SwiftUI

extension SelectUserView {

    struct AddUserGridButton: View {

        @Environment(\.colorScheme)
        private var colorScheme
        @Environment(\.isEnabled)
        private var isEnabled

        let selectedServer: ServerState?
        let servers: OrderedSet<ServerState>
        let action: (ServerState) -> Void

        private var avatarSide: CGFloat {
            UIDevice.isPhone ? 150 : 190
        }

        @ViewBuilder
        private var label: some View {
            VStack(alignment: .center, spacing: 10) {
                ZStack {
                    Group {
                        if colorScheme == .light {
                            Color.secondarySystemFill
                        } else {
                            Color.tertiarySystemBackground
                        }
                    }
                    .posterShadow()

                    RelativeSystemImageView(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
                .clipShape(.circle)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: avatarSide, height: avatarSide)

                Text(L10n.addUser)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if selectedServer == nil {
                    // swiftlint:disable:next hard_coded_display_string
                    Text("Hidden")
                        .font(.footnote)
                        .hidden()
                }
            }
        }

        var body: some View {
            ConditionalMenu(
                tracking: selectedServer,
                action: action
            ) {
                Text(L10n.selectServer)

                ForEach(servers) { server in
                    Button {
                        action(server)
                    } label: {
                        Text(server.name)
                        Text(server.currentURL.absoluteString)
                    }
                }
            } label: {
                label
            }
            .buttonStyle(.plain)
            .frame(maxWidth: UIDevice.isPhone ? 190 : 240)
        }
    }
}
