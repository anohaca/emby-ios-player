//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import PreferencesView
import SwiftUI
import Transmission
#if os(iOS)
import UIKit
#endif

// TODO: have full screen zoom presentation zoom from/to center
//       - probably need to make mock view with matching ids
// TODO: have presentation dismissal be through preference keys
//       - issue with all of the VC/view wrapping

extension EnvironmentValues {

    @Entry
    var presentationControllerShouldDismiss: Binding<Bool> = .constant(true)

    @Entry
    var dismissPresentedNavigationRoute: (((@MainActor () -> Void)?) -> Void)?
}

struct NavigationInjectionView: View {

    @StateObject
    private var coordinator: NavigationCoordinator
    @EnvironmentObject
    private var rootCoordinator: RootCoordinator

    @State
    private var isPresentationInteractive: Bool = true
    @State
    private var presentedNativeFullScreenDismissCompletion: (@MainActor () -> Void)?
    @State
    private var presentedFullScreenDismissCompletion: (@MainActor () -> Void)?

    private let content: AnyView

    init(
        coordinator: @autoclosure @escaping () -> NavigationCoordinator,
        @ViewBuilder content: @escaping () -> some View
    ) {
        _coordinator = StateObject(wrappedValue: coordinator())
        self.content = AnyView(content())
    }

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            content
                .navigationDestination(for: NavigationRoute.self) { route in
                    route.destination
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmbyAppBackgroundView())
        .environment(
            \.router,
            .init(
                navigationCoordinator: coordinator,
                rootCoordinator: rootCoordinator
            )
        )
        #if os(tvOS)
        // TODO: Workaround for sheet presentation issue on tvOS
        // https://developer.apple.com/documentation/tvos-release-notes/tvos-26_1-release-notes
        // Remove this tvOS section when resolved
        .fullScreenCover(
                item: $coordinator.presentedSheet
            ) {
                coordinator.presentedSheet = nil
            } content: { route in
                let newCoordinator = NavigationCoordinator()

                NavigationInjectionView(coordinator: newCoordinator) {
                    route.destination
                }
                .environmentObject(rootCoordinator)
                .background(EmbyAppBackgroundView())
                .background(.regularMaterial)
            }
        #else // <- Start: Use this for both OS when fixed
            .sheet(
                item: $coordinator.presentedSheet
            ) {
                coordinator.presentedSheet = nil
            } content: { route in
                let newCoordinator = NavigationCoordinator()

                NavigationInjectionView(coordinator: newCoordinator) {
                    route.destination
                }
                .environmentObject(rootCoordinator)
                .background(EmbyAppBackgroundView())
            }
        #endif // <- End
        #if os(tvOS)
        .fullScreenCover(
            item: $coordinator.presentedFullScreen
        ) { route in
            let newCoordinator = NavigationCoordinator()

            NavigationInjectionView(coordinator: newCoordinator) {
                route.destination
            }
            .environmentObject(rootCoordinator)
            .background(EmbyAppBackgroundView())
        }
        #else
            .fullScreenCover(
                item: $coordinator.presentedNativeFullScreen
            ) {
                guard let completion = presentedNativeFullScreenDismissCompletion else { return }
                presentedNativeFullScreenDismissCompletion = nil

                #if DEBUG
                NSLog("EmbyNavigation dismiss completed target=native-fullscreen-host")
                #endif

                completion()
            } content: { route in
                let newCoordinator = NavigationCoordinator()

                NavigationInjectionView(coordinator: newCoordinator) {
                    route.destination
                        .environment(\.presentationControllerShouldDismiss, $isPresentationInteractive)
                        .environment(\.dismissPresentedNavigationRoute) { completion in
                            #if DEBUG
                            NSLog("EmbyNavigation dismiss target=direct-native-fullscreen-binding route=%@", coordinator.presentedNativeFullScreen?.id ?? "nil")
                            #endif
                            presentedNativeFullScreenDismissCompletion = completion
                            coordinator.presentedNativeFullScreen = nil
                        }
                }
                .environmentObject(rootCoordinator)
                .background(EmbyAppBackgroundView())
            }
            .presentation(
                $coordinator.presentedFullScreen,
                transition: .zoomIfAvailable(
                    options: .init(
                        prefersScalePresentingView: false,
                        options: .init(
                            isInteractive: isPresentationInteractive,
                            preferredPresentationBackgroundColor: .clear
                        )
                    ),
                    otherwise: .slide(
                        edge: .bottom,
                        prefersScaleEffect: false,
                        isInteractive: isPresentationInteractive,
                        preferredPresentationBackgroundColor: .clear
                    )
                )
            ) { routeBinding, _ -> UIViewController in
                let vc = UIPreferencesHostingController {
                    NavigationInjectionView(coordinator: .init()) {
                        routeBinding.wrappedValue.destination
                            .environment(\.presentationControllerShouldDismiss, $isPresentationInteractive)
                            .environment(\.dismissPresentedNavigationRoute) { completion in
                                #if DEBUG
                                NSLog("EmbyNavigation dismiss target=direct-fullscreen-binding route=%@", coordinator.presentedFullScreen?.id ?? "nil")
                                #endif
                                presentedFullScreenDismissCompletion = completion
                                coordinator.presentedFullScreen = nil

                                guard completion != nil else { return }

                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(1400))
                                    guard let completion = presentedFullScreenDismissCompletion else { return }
                                    presentedFullScreenDismissCompletion = nil

                                    #if DEBUG
                                    NSLog("EmbyNavigation dismiss completed target=direct-fullscreen-host source=fallback")
                                    #endif

                                    completion()
                                }
                            }
                    }
                    .environmentObject(rootCoordinator)
                }
                vc.view.backgroundColor = .clear
                vc.onDidDisappearAfterDismiss = {
                    guard let completion = presentedFullScreenDismissCompletion else { return }
                    presentedFullScreenDismissCompletion = nil

                    #if DEBUG
                    NSLog("EmbyNavigation dismiss completed target=direct-fullscreen-host source=viewDidDisappear")
                    #endif

                    completion()
                }
                return vc
            }
        #endif
    }
}
