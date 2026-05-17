//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationRoute {

    static var connectToServer: NavigationRoute {
        NavigationRoute(
            id: "connectToServer",
            style: .sheet
        ) {
            ConnectToServerView()
        }
    }

    #if os(iOS)
    static func userProfileImage(viewModel: UserProfileImageViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "userProfileImage",
            style: .sheet
        ) {
            UserProfileImagePickerView(viewModel: viewModel)
        }
    }

    static func userProfileImageCrop(viewModel: UserProfileImageViewModel, image: UIImage) -> NavigationRoute {
        NavigationRoute(
            id: "cropImage",
            style: .sheet
        ) {
            UserProfileImageCropView(
                viewModel: viewModel,
                image: image
            )
        }
    }

    // TODO: rename to `localUserAccessPolicy`
    static func userSecurity(pinHint: Binding<String>, accessPolicy: Binding<UserAccessPolicy>) -> NavigationRoute {
        NavigationRoute(
            id: "userSecurity",
            style: .sheet
        ) {
            LocalUserAccessPolicyView(
                pinHint: pinHint,
                accessPolicy: accessPolicy
            )
        }
    }
    #endif

    static func userSignIn(
        server: ServerState,
        username: String = "",
        reauthenticatingUserID: String? = nil
    ) -> NavigationRoute {
        NavigationRoute(
            id: "userSignIn-\(server.id)-\(reauthenticatingUserID ?? username)",
            style: .fullscreen
        ) {
            WithUserAuthentication {
                UserSignInView(
                    server: server,
                    username: username,
                    reauthenticatingUserID: reauthenticatingUserID
                )
            }
        }
    }
}
