//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import PreferencesView
import SwiftUI
import UIKit

@MainActor
final class EmbyPlayerWindowPresenter {

    static let shared = EmbyPlayerWindowPresenter()

    private var window: UIWindow?

    private init() {}

    func present<Content: View>(
        in scene: UIWindowScene?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        dismiss()

        guard let scene = scene ?? Self.foregroundWindowScene else {
            #if DEBUG
            NSLog("EmbyPlayerWindow present=failed reason=missing-scene")
            #endif
            return
        }

        let hostingController = UIPreferencesHostingController {
            content()
                .ignoresSafeArea()
        }
        hostingController.view.backgroundColor = .clear
        hostingController.supportedOrientationsOverride = .landscape
        hostingController.preferredInterfaceOrientationOverride = .landscapeRight

        let window = UIWindow(windowScene: scene)
        window.rootViewController = hostingController
        window.backgroundColor = .clear
        window.windowLevel = .normal + 10
        window.isHidden = false
        window.makeKeyAndVisible()
        self.window = window

        #if DEBUG
        NSLog("EmbyPlayerWindow present=success sceneOrientation=%d", scene.interfaceOrientation.rawValue)
        #endif
    }

    func dismiss() {
        guard let window else { return }

        #if DEBUG
        NSLog("EmbyPlayerWindow dismiss")
        #endif

        window.isHidden = true
        window.rootViewController = nil
        self.window = nil
    }

    private static var foregroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    }
}
#endif
