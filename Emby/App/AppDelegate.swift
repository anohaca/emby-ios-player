//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import PreferencesView
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    static var phoneOrientationLock: UIInterfaceOrientationMask?

    private var windowBackgroundObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        windowBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            (notification.object as? UIWindow)?.applyEmbyAppBackground()
        }

        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {

        guard UIDevice.isPhone else {
            return .allButUpsideDown
        }

        if let phoneOrientationLock = AppDelegate.phoneOrientationLock {
            return phoneOrientationLock
        }

        if let presentedViewController = window?.rootViewController?.presentedViewController,
           presentedViewController.supportedInterfaceOrientations == .landscape
        {
            return .landscape
        }

        if let presentedViewController = window?.rootViewController?.presentedViewController,
           let preferencesHostingController = preferencesHostingController(from: presentedViewController)
        {
            let orientations = preferencesHostingController.supportedInterfaceOrientations
            return orientations
        }

        return .portrait
    }

    private func preferencesHostingController(from controller: UIViewController?) -> UIPreferencesHostingController? {
        if let preferencesHostingController = controller as? UIPreferencesHostingController {
            return preferencesHostingController
        }

        for child in controller?.children ?? [] {
            if let preferencesHostingController = preferencesHostingController(from: child) {
                return preferencesHostingController
            }
        }

        return nil
    }

}
extension UIWindow {

    var isEmbyAppContentWindow: Bool {
        String(describing: type(of: self)) == "UIWindow"
    }

    func applyEmbyAppBackground() {
        guard isEmbyAppContentWindow else { return }
        backgroundColor = .embyAppBackground
        rootViewController?.view.backgroundColor = .embyAppBackground
    }
}
