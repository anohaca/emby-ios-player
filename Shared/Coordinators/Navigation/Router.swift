//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension NavigationCoordinator {

    @MainActor
    struct Router {

        let navigationCoordinator: NavigationCoordinator?
        let rootCoordinator: RootCoordinator?

        func route(
            to route: NavigationRoute,
            transition: NavigationRoute.TransitionType? = nil,
            in namespace: Namespace.ID? = nil
        ) {
            var route = route
            route.namespace = namespace
            route.transitionType = transition ?? route.transitionType
            navigationCoordinator?.push(route)
        }

        func root(
            _ root: RootItem
        ) {
            rootCoordinator?.root(root)
        }

        func popToRoot() {
            navigationCoordinator?.path.removeAll()
            navigationCoordinator?.presentedSheet = nil
            navigationCoordinator?.presentedNativeFullScreen = nil
            navigationCoordinator?.presentedFullScreen = nil
        }

        @discardableResult
        func dismissTopRoute() -> Bool {
            guard let navigationCoordinator else { return false }

            if navigationCoordinator.presentedNativeFullScreen != nil {
                navigationCoordinator.presentedNativeFullScreen = nil
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=native-fullscreen")
                #endif
                return true
            }

            if navigationCoordinator.presentedFullScreen != nil {
                navigationCoordinator.presentedFullScreen = nil
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=fullscreen")
                #endif
                return true
            }

            if navigationCoordinator.presentedSheet != nil {
                navigationCoordinator.presentedSheet = nil
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=sheet")
                #endif
                return true
            }

            if !navigationCoordinator.path.isEmpty {
                let routeID = navigationCoordinator.path.last?.id ?? "unknown"
                navigationCoordinator.path.removeLast()
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=path route=%@ remaining=%d", routeID, navigationCoordinator.path.count)
                #endif
                return true
            }

            return false
        }

        func returnHome() {
            popToRoot()
            rootCoordinator?.root(.mainTab)
        }
    }
}

@propertyWrapper
struct Router: DynamicProperty {

    @MainActor
    struct Wrapper {
        let router: NavigationCoordinator.Router
        let systemDismiss: DismissAction
        let presentationDismiss: (((@MainActor () -> Void)?) -> Void)?

        func route(
            to route: NavigationRoute,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: nil,
                in: namespace
            )
        }

        func route(
            to route: NavigationRoute,
            style: NavigationRoute.TransitionStyle,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: .automatic(style),
                in: namespace
            )
        }

        func route(
            to route: NavigationRoute,
            withNamespace: @escaping (Namespace.ID) -> NavigationRoute.TransitionStyle,
            in namespace: Namespace.ID? = nil
        ) {
            router.route(
                to: route,
                transition: .withNamespace(withNamespace),
                in: namespace
            )
        }

        func root(
            _ root: RootItem
        ) {
            router.root(root)
        }

        func popToRoot() {
            router.popToRoot()
        }

        func returnHome() {
            router.returnHome()
        }

        func dismiss() {
            guard !router.dismissTopRoute() else { return }

            if let presentationDismiss {
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=presentation")
                #endif
                presentationDismiss(nil)
                return
            }

            #if DEBUG
            NSLog("EmbyNavigation dismiss target=system")
            #endif
            systemDismiss()
        }

        func dismiss(afterPresentationDismiss completion: @escaping @MainActor () -> Void) {
            if router.dismissTopRoute() {
                Task { @MainActor in
                    completion()
                }
                return
            }

            if let presentationDismiss {
                #if DEBUG
                NSLog("EmbyNavigation dismiss target=presentation completion=deferred")
                #endif
                presentationDismiss(completion)
                return
            }

            #if DEBUG
            NSLog("EmbyNavigation dismiss target=system completion=immediate")
            #endif
            systemDismiss()

            Task { @MainActor in
                completion()
            }
        }
    }

    // `.dismiss` causes changes on disappear
    @Environment(\.self)
    private var environment

    var wrappedValue: Wrapper {
        return .init(
            router: environment.router,
            systemDismiss: environment.dismiss,
            presentationDismiss: environment.dismissPresentedNavigationRoute
        )
    }
}

extension EnvironmentValues {

    @Entry
    var router: NavigationCoordinator.Router = .init(
        navigationCoordinator: nil,
        rootCoordinator: nil
    )
}
