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
import KeychainSwift
import Logging
import Pulse
import UIKit

extension EmbyStore.State {

    struct User: Hashable, Identifiable, Codable {
        let id: String
        let serverID: String
        let username: String
    }
}

extension UserState {

    typealias Key = StoredValues.Key

    var accessTokenIfAvailable: String? {
        Container.shared.keychainService().get(accessTokenKey) ?? fallbackAccessToken
    }

    @discardableResult
    func storeAccessToken(_ accessToken: String) -> Bool {
        let keychain = Container.shared.keychainService()

        if keychain.set(accessToken, forKey: accessTokenKey) {
            clearFallbackAccessToken()
            return true
        }

        #if DEBUG && targetEnvironment(simulator)
        fallbackAccessToken = accessToken
        Logger.emby().warning(
            "Stored access token in simulator fallback after Keychain write failed with status \(keychain.lastResultCode)"
        )
        return true
        #else
        Logger.emby().error(
            "Failed to store access token in Keychain with status \(keychain.lastResultCode)"
        )
        return false
        #endif
    }

    var accessToken: String {
        get {
            accessTokenIfAvailable ?? ""
        }
        nonmutating set {
            storeAccessToken(newValue)
        }
    }

    var data: UserDto {
        get {
            StoredValues[.User.data(id: id)]
        }
        nonmutating set {
            StoredValues[.User.data(id: id)] = newValue
        }
    }

    var pin: String {
        get {
            guard let pin = Container.shared.keychainService().get("\(id)-pin") else {
                assertionFailure("pin missing in keychain")
                return ""
            }

            return pin
        }
        nonmutating set {
            Container.shared.keychainService().set(newValue, forKey: "\(id)-pin")
        }
    }

    var pinHint: String {
        get {
            StoredValues[.User.pinHint(id: id)]
        }
        nonmutating set {
            StoredValues[.User.pinHint(id: id)] = newValue
        }
    }

    var accessPolicy: UserAccessPolicy {
        get {
            StoredValues[.User.accessPolicy(id: id)]
        }
        nonmutating set {
            StoredValues[.User.accessPolicy(id: id)] = newValue
        }
    }

    private var accessTokenKey: String {
        "\(id)-accessToken"
    }

    private var fallbackAccessTokenKey: String {
        "\(id)-accessToken-fallback"
    }

    private var fallbackAccessToken: String? {
        get {
            #if DEBUG && targetEnvironment(simulator)
            UserDefaults.standard.string(forKey: fallbackAccessTokenKey)
            #else
            nil
            #endif
        }
        nonmutating set {
            #if DEBUG && targetEnvironment(simulator)
            UserDefaults.standard.set(newValue, forKey: fallbackAccessTokenKey)
            #endif
        }
    }

    private func clearFallbackAccessToken() {
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: fallbackAccessTokenKey)
        #endif
    }
}

extension UserState {

    /// Deletes the model that this state represents and
    /// all settings from `Defaults` `Keychain`, and `StoredValues`
    func delete() throws {
        var users = StoredValues[.User.users]
        users.removeAll { $0.id == id }
        StoredValues[.User.users] = users

        try deleteSettings()

        var servers = StoredValues[.Server.servers]
        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            let currentServer = servers[index]

            servers[index] = ServerState(
                urls: currentServer.urls,
                currentURL: currentServer.currentURL,
                name: currentServer.name,
                id: currentServer.id,
                userIDs: currentServer.userIDs.filter { $0 != id }
            )

            StoredValues[.Server.servers] = servers
        }

        let keychain = Container.shared.keychainService()
        keychain.delete("\(id)-accessToken")
        keychain.delete("\(id)-pin")
        clearFallbackAccessToken()
    }

    /// Deletes user settings from `UserDefaults` and `StoredValues`
    func deleteSettings() throws {
        try AnyStoredData.deleteAll(ownerID: id)
        UserDefaults.userSuite(id: id).removeAll()
    }

    /// Must pass the server to create an authenticated Emby session
    /// with an access token.
    func getUserData(server: ServerState) async throws -> UserDto {
        let client = EmbyPortSessionClient(
            configuration: EmbyPortSessionConfiguration(
                baseURL: server.currentURL,
                accessToken: accessToken,
                userID: id,
                identity: .embyDefault()
            )
        )

        return try await client.currentUser(as: UserDto.self)
    }

    // we will always crop to a square, so just use width
    func profileImageSource(
        client: EmbyPortSessionClient,
        maxWidth: CGFloat? = nil
    ) -> ImageSource {
        let scaleWidth: Int? = maxWidth == nil ? nil : UIScreen.main.scale(maxWidth!)
        let imageWidth = scaleWidth ?? maxWidth.map(Int.init)
        let profileImageURL = client.userImageURL(
            userID: id,
            maxWidth: imageWidth.map(Double.init)
        )

        return ImageSource(url: profileImageURL)
    }

}
