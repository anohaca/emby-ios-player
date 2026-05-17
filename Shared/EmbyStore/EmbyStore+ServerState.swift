//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Factory
import Foundation
import Pulse

extension EmbyStore.State {

    struct Server: Hashable, Identifiable, Codable {

        let urls: Set<URL>
        let currentURL: URL
        let name: String
        let id: String
        let userIDs: [String]

        var embyAuthenticationClient: EmbyPortAuthenticationClient {
            EmbyPortAuthenticationClient(
                baseURL: currentURL,
                identity: .embyDefault()
            )
        }
    }
}

extension ServerState {

    func embySessionClient(userID: String = "", accessToken: String = "") -> EmbyPortSessionClient {
        EmbyPortSessionClient(
            configuration: EmbyPortSessionConfiguration(
                baseURL: currentURL,
                accessToken: accessToken,
                userID: userID,
                identity: .embyDefault()
            )
        )
    }

    /// Deletes the model that this state represents and
    /// all settings from `StoredValues`.
    func delete() throws {
        let users = StoredValues[.User.users]
            .filter { $0.serverID == id }

        for user in users {
            try AnyStoredData.deleteAll(ownerID: user.id)
        }
        try AnyStoredData.deleteAll(ownerID: id)

        var storedUsers = StoredValues[.User.users]
        storedUsers.removeAll { $0.serverID == id }
        StoredValues[.User.users] = storedUsers

        var servers = StoredValues[.Server.servers]
        servers.removeAll { $0.id == id }
        StoredValues[.Server.servers] = servers

        for user in users {
            UserDefaults.userSuite(id: user.id).removeAll()
        }
    }

    func getPublicSystemInfo() async throws -> PublicSystemInfo {
        let response = try await embyAuthenticationClient.publicSystemInfo().info

        var info = PublicSystemInfo()
        info.id = response.id
        info.serverName = response.name
        info.version = response.version
        return info
    }

    var splashScreenImageSource: ImageSource {
        ImageSource(url: embySessionClient().splashscreenURL())
    }

    @MainActor
    func updateServerInfo() async throws {
        let servers = StoredValues[.Server.servers]
        guard let currentServer = servers.first(where: { $0.id == id }) else { return }

        let publicInfo = try await getPublicSystemInfo()
        let updatedName = publicInfo.serverName ?? currentServer.name

        let updatedServer = ServerState(
            urls: currentServer.urls,
            currentURL: currentServer.currentURL,
            name: updatedName,
            id: currentServer.id,
            userIDs: currentServer.userIDs
        )

        StoredValues[.Server.servers] = servers.map { $0.id == id ? updatedServer : $0 }
        StoredValues[.Server.publicInfo(id: currentServer.id)] = publicInfo
    }

    var isVersionCompatible: Bool {
        let publicInfo = StoredValues[.Server.publicInfo(id: self.id)]
        return publicInfo.version != nil
    }
}
