//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

@MainActor
final class NavigationCoordinator: ObservableObject {

    @Published
    var path: [NavigationRoute] = []

    @Published
    var presentedSheet: NavigationRoute?
    @Published
    var presentedNativeFullScreen: NavigationRoute?
    @Published
    var presentedFullScreen: NavigationRoute?

    func push(
        _ route: NavigationRoute
    ) {
        let style = route.transitionStyle

        #if DEBUG
        let styleName: String
        switch style {
        case .push:
            styleName = "push"
        case .sheet:
            styleName = "sheet"
        case .fullscreen:
            styleName = "fullscreen"
        }
        NSLog("EmbyNavigation push route=%@ style=%@", route.id, styleName)
        #endif

        #if os(tvOS)
        switch style {
        case .push, .sheet:
            presentedSheet = route
        case .fullscreen:
            presentedFullScreen = route
        }
        #else
        switch style {
        case .push:
            path.append(route)
        case .sheet:
            presentedSheet = route
        case .fullscreen:
            if route.id.hasPrefix("userSignIn-") {
                presentedNativeFullScreen = route
                return
            }

            if route.id == NavigationRoute.videoPlayerID {
                #if os(iOS)
                EmbyLibMPVPlayerViewController.prepareLandscapeOrientationForPresentation(requestSceneImmediately: false)
                #endif
                withAnimation {
                    presentedFullScreen = route
                }
            } else {
                withAnimation {
                    presentedFullScreen = route
                }
            }
        }
        #endif
    }
}
