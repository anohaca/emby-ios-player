//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory

final class UserSession {

    let embyClient: EmbyPortSessionClient
    let server: ServerState
    let user: UserState

    init(
        server: ServerState,
        user: UserState,
        accessToken: String
    ) {
        self.server = server
        self.user = user

        self.embyClient = EmbyPortSessionClient(
            configuration: EmbyPortSessionConfiguration(
                baseURL: server.currentURL,
                accessToken: accessToken,
                userID: user.id,
                identity: .embyDefault()
            )
        )
    }
}

extension Container {

    // TODO: be parameterized, take user id
    //       - don't be optional
    //       - in `ViewModel`, don't be implicitly unwrapped
    //         and have idempotent default value
    var currentUserSession: Factory<UserSession?> {
        self {
            guard case let .signedIn(userId) = Defaults[.lastSignedInUserID] else { return nil }

            guard let user = StoredValues[.User.users].first(where: { $0.id == userId }) else {
                // had last user ID but no saved user
                Defaults[.lastSignedInUserID] = .signedOut

                return nil
            }

            guard let server = StoredValues[.Server.servers].first(where: { $0.id == user.serverID }) else {
                Defaults[.lastSignedInUserID] = .signedOut
                return nil
            }

            guard let accessToken = user.accessTokenIfAvailable, !accessToken.isEmpty else {
                Defaults[.lastSignedInUserID] = .signedOut
                return nil
            }

            return .init(
                server: server,
                user: user,
                accessToken: accessToken
            )
        }.cached
    }
}
