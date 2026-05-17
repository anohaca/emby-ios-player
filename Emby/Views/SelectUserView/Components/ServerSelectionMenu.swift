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

    struct ServerSelectionMenu: View {

        @Environment(\.colorScheme)
        private var colorScheme

        @Router
        private var router

        @Binding
        private var serverSelection: SelectUserServerSelection

        let selectedServer: ServerState?
        let servers: OrderedSet<ServerState>

        init(
            selection: Binding<SelectUserServerSelection>,
            selectedServer: ServerState?,
            servers: OrderedSet<ServerState>
        ) {
            self._serverSelection = selection
            self.selectedServer = selectedServer
            self.servers = servers
        }

        var body: some View {
            Menu {
                Section {
                    Button(L10n.addServer, systemImage: "plus") {
                        router.route(to: .connectToServer)
                    }

                    if let selectedServer {
                        Button(L10n.editServer, systemImage: "server.rack") {
                            router.route(
                                to: .editServer(server: selectedServer, isEditing: true),
                                style: .sheet
                            )
                        }
                    }
                }

                Picker(L10n.servers, selection: _serverSelection) {

                    if servers.count > 1 {
                        Label(L10n.allServers, systemImage: "person.2.fill")
                            .tag(SelectUserServerSelection.all)
                    }

                    ForEach(servers.reversed()) { server in
                        Button {} label: {
                            Text(server.name)
                            Text(server.currentURL.absoluteString)
                        }
                        .tag(SelectUserServerSelection.server(id: server.id))
                    }
                }
            } label: {
                ZStack {

                    Capsule()
                        .fill(.ultraThinMaterial)

                    Capsule()
                        .fill(colorScheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.08))

                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.45 : 0.14), lineWidth: 1)

                    HStack(spacing: 10) {
                        switch serverSelection {
                        case .all:
                            Label(L10n.allServers, systemImage: "person.2.fill")
                        case let .server(id):
                            if let server = servers.first(where: { $0.id == id }) {
                                Label(server.name, systemImage: "server.rack")
                            }
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 18)
                }
                .frame(height: 44)
                .frame(maxWidth: UIDevice.isPhone ? 340 : 400)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
