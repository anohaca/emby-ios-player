//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Defaults
import Factory
import Logging
import Nuke
import PreferencesView
import PulseLogHandler
import SwiftUI

@main
struct EmbyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @StateObject
    private var valueObservation = ValueObservation()

    @Default(.appearance)
    private var appearance

    @ViewBuilder
    private var appRootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-EmbySettingsSmokeRoot") {
            NavigationStack {
                SettingsView()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySettingsSmokeHomeSections") {
            NavigationStack {
                HomeSectionSettingsView()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySettingsSmokeVideoPlayer") {
            NavigationStack {
                VideoPlayerSettingsView()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySettingsSmokeGestures") {
            NavigationStack {
                GestureSettingsView()
            }
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyPlayerLocalizationSmoke") {
            DebugPlayerLocalizationSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySubtitleAdjustmentSmoke") {
            DebugSubtitleAdjustmentSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySelectUserInitialServerSmoke") {
            DebugSelectUserInitialServerSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySubtitleLanguageSmoke") {
            DebugSubtitleLanguageSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyCompatibilitySmoke") {
            DebugCompatibilitySmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyFavoritesSmoke") {
            DebugFavoritesSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbySearchSmoke") {
            DebugSearchSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyFilterSmokeSort") {
            NavigationStack {
                FilterView(viewModel: FilterViewModel(currentFilters: .recent), type: .sortBy)
            }
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInDismissSmoke") ||
            ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInSavedDismissSmoke") ||
            ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInRealSmokeUsername")
        {
            DebugUserSignInDismissSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyAddServerUserCompleteSmoke") {
            DebugAddServerUserCompleteSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-EmbyNavigationDismissSmoke") {
            DebugNavigationDismissSmokeView()
        } else if DebugPlaybackSmokeRunner.configuration != nil {
            DebugPlaybackSmokeView()
        } else if DebugLoginSmokeRunner.configuration != nil {
            DebugLoginSmokeView()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

    init() {

        #if DEBUG
        SwizzleDefaults.set(true, for: "com.apple.SwiftUI.IgnoreSolariumOptOut")
        #endif

        // Logging
        LoggingSystem.bootstrap { label in

            // TODO: have setting for log level
            //       - default info, boolean to go down to trace
            let handlers: [any LogHandler] = [PersistentLogHandler(label: label)]
            #if DEBUG
                .appending(EmbyConsoleHandler())
            #endif

            var multiplexHandler = MultiplexLogHandler(handlers)
            multiplexHandler.logLevel = .trace
            return multiplexHandler
        }

        // CoreStore

        CoreStoreDefaults.dataStack = EmbyStore.dataStack
        CoreStoreDefaults.logger = EmbyCorestoreLogger()

        // Nuke

        ImageCache.shared.costLimit = 1024 * 1024 * 200 // 200 MB
        ImageCache.shared.ttl = 300 // 5 min

        ImageDecoderRegistry.shared.register { context in
            guard let mimeType = context.urlResponse?.mimeType else { return nil }
            return mimeType.contains("svg") ? ImageDecoders.Empty() : nil
        }

        ImagePipeline.shared = .Emby.posters

        // UIKit

        if Defaults[.appearance] != .dark {
            Defaults[.appearance] = .dark
        }

        if Defaults[.appAppearance] != .dark {
            Defaults[.appAppearance] = .dark
        }

        if Defaults[.userAppearance] != .dark {
            Defaults[.userAppearance] = .dark
        }

        UIScrollView.appearance().keyboardDismissMode = .onDrag
        UIScrollView.appearance().backgroundColor = .embyAppBackground
        UITableView.appearance().backgroundColor = .embyAppBackground
        UITableViewCell.appearance().backgroundColor = .embyAppBackgroundSurface
        UICollectionView.appearance().backgroundColor = .embyAppBackground

        // Sometimes the tab bar won't appear properly on push, always have material background
        let tabBarAppearance = UITabBarAppearance(idiom: .unspecified)
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor.embyAppBackground.withAlphaComponent(0.78)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithTransparentBackground()
        navigationBarAppearance.backgroundColor = .clear
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance

        // Emby

        // don't keep last user id
        if Defaults[.signOutOnClose] {
            Defaults[.lastSignedInUserID] = .signedOut
        }

        EmbySpotlight().addEmbyToSpotlight()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                EmbyAppBackgroundView()

                OverlayToastView {
                    PreferencesView {
                        appRootView
                            .supportedOrientations(.allButUpsideDown)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EmbyAppBackgroundView())
            .ignoresSafeArea()
            .onAppear {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .forEach { window in
                        guard window.isEmbyAppContentWindow else { return }
                        window.applyEmbyAppBackground()
                        window.overrideUserInterfaceStyle = appearance.style
                    }
            }
            .preferredColorScheme(appearance.colorScheme)
            .onAppDidEnterBackground {
                Defaults[.backgroundTimeStamp] = Date.now
            }
            .onAppWillEnterForeground {

                // TODO: needs to check if any background playback is happening
                //       - atow, background video playback isn't officially supported
                let backgroundedInterval = Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp])

                if Defaults[.signOutOnBackground], backgroundedInterval > Defaults[.backgroundSignOutInterval] {
                    Defaults[.lastSignedInUserID] = .signedOut
                    Container.shared.currentUserSession.reset()
                    Notifications[.didSignOut].post()
                }
            }
        }
    }
}

#if DEBUG
private struct DebugFavoritesSmokeView: View {

    enum SmokeState {
        case loading
        case content
        case failed(String)
    }

    @State
    private var state: SmokeState = .loading

    var body: some View {
        NavigationStack {
            switch state {
            case .loading:
                ProgressView("FAVORITES_SMOKE_LOADING")
            case .content:
                FavoritesView()
            case let .failed(message):
                VStack(spacing: 12) {
                    Text("FAVORITES_SMOKE_FAIL")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task {
            guard case .loading = state else { return }

            do {
                try await EmbyStore.setupDataStack()

                guard Container.shared.currentUserSession() != nil else {
                    state = .failed("Missing current user session")
                    return
                }

                state = .content
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@MainActor
private struct DebugUserSignInDismissSmokeView: View {

    @StateObject
    private var coordinator = NavigationCoordinator()
    @StateObject
    private var rootCoordinator = RootCoordinator()

    @State
    private var didStart = false
    @State
    private var status = "USER_SIGN_IN_DISMISS_SMOKE_START"

    private var isSavedDismissSmoke: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInSavedDismissSmoke")
    }

    private var realSmokeCredentials: (username: String, password: String)? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let username = arguments.value(after: "-EmbyUserSignInRealSmokeUsername"),
              let password = arguments.value(after: "-EmbyUserSignInRealSmokePassword")
        else {
            return nil
        }

        return (username, password)
    }

    var body: some View {
        NavigationInjectionView(coordinator: coordinator) {
            ZStack {
                EmbyAppBackgroundView()

                Text(status)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .onAppear(perform: startIfNeeded)
        }
        .environmentObject(rootCoordinator)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        Task { @MainActor in
            do {
                try await EmbyStore.setupDataStack()
                let storedServers = StoredValues[.Server.servers]
                guard let firstServer = storedServers.first else {
                    status = "USER_SIGN_IN_DISMISS_SMOKE_FAIL"
                    NSLog("USER_SIGN_IN_DISMISS_SMOKE_FAIL missing-server")
                    return
                }

                let originalSignInState = Defaults[.lastSignedInUserID]
                let originalUsers = StoredValues[.User.users]
                let originalServers = StoredValues[.Server.servers]
                let username: String
                let server: ServerState
                let isRealSmoke = realSmokeCredentials != nil

                if let realSmokeCredentials {
                    status = "USER_SIGN_IN_REAL_SMOKE_START"
                    username = realSmokeCredentials.username
                    server = realSmokeServer(username: username, servers: storedServers) ?? firstServer
                    let existingLocalUser = StoredValues[.User.users].contains {
                        $0.serverID == server.id && $0.username == username
                    }
                    removeRealSmokeLocalUser(username: username, server: server)
                    NSLog(
                        "USER_SIGN_IN_REAL_SMOKE_START server=%@ url=%@ username=%@ existingLocalUser=%@",
                        server.name,
                        server.currentURL.absoluteString,
                        username,
                        existingLocalUser ? "true" : "false"
                    )
                } else if isSavedDismissSmoke {
                    status = "USER_SIGN_IN_SAVED_DISMISS_SMOKE_START"
                    server = firstServer
                    username = prepareSavedDismissSmokeUser(server: server).username
                } else {
                    server = firstServer
                    username = "ioidd"
                }

                defer {
                    if isSavedDismissSmoke || isRealSmoke {
                        StoredValues[.User.users] = originalUsers
                        StoredValues[.Server.servers] = originalServers
                        Defaults[.lastSignedInUserID] = originalSignInState
                        Container.shared.currentUserSession.reset()
                    }
                }

                coordinator.push(.userSignIn(server: server, username: username))

                try? await Task.sleep(for: .milliseconds(isRealSmoke ? 8000 : (isSavedDismissSmoke ? 2200 : 1400)))
                if coordinator.presentedNativeFullScreen == nil, coordinator.presentedFullScreen == nil {
                    if isRealSmoke {
                        status = "USER_SIGN_IN_REAL_SMOKE_PASS"
                    } else if isSavedDismissSmoke {
                        status = "USER_SIGN_IN_SAVED_DISMISS_SMOKE_PASS"
                    } else {
                        status = "USER_SIGN_IN_DISMISS_SMOKE_PASS"
                    }
                    NSLog(
                        "%@ presentedFullScreen=nil root=%@",
                        status,
                        rootCoordinator.root.id
                    )
                } else {
                    if isRealSmoke {
                        status = "USER_SIGN_IN_REAL_SMOKE_FAIL"
                    } else if isSavedDismissSmoke {
                        status = "USER_SIGN_IN_SAVED_DISMISS_SMOKE_FAIL"
                    } else {
                        status = "USER_SIGN_IN_DISMISS_SMOKE_FAIL"
                    }
                    NSLog(
                        "%@ presentedNativeFullScreen=%@ presentedFullScreen=%@ root=%@",
                        status,
                        coordinator.presentedNativeFullScreen?.id ?? "nil",
                        coordinator.presentedFullScreen?.id ?? "unknown",
                        rootCoordinator.root.id
                    )
                }
            } catch {
                status = isSavedDismissSmoke ? "USER_SIGN_IN_SAVED_DISMISS_SMOKE_FAIL" : "USER_SIGN_IN_DISMISS_SMOKE_FAIL"
                NSLog("%@ error=%@", status, error.localizedDescription)
            }
        }
    }

    private func realSmokeServer(username: String, servers: [ServerState]) -> ServerState? {
        guard let user = StoredValues[.User.users].first(where: { $0.username == username }) else {
            return nil
        }

        return servers.first { $0.id == user.serverID }
    }

    private func removeRealSmokeLocalUser(username: String, server: ServerState) {
        var users = StoredValues[.User.users]
        let removedIDs = Set(users.filter { $0.serverID == server.id && $0.username == username }.map(\.id))
        guard !removedIDs.isEmpty else { return }

        users.removeAll { removedIDs.contains($0.id) }
        StoredValues[.User.users] = users

        var servers = StoredValues[.Server.servers]
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            let existingServer = servers[index]
            servers[index] = ServerState(
                urls: existingServer.urls,
                currentURL: existingServer.currentURL,
                name: existingServer.name,
                id: existingServer.id,
                userIDs: existingServer.userIDs.filter { !removedIDs.contains($0) }
            )
            StoredValues[.Server.servers] = servers
        }
    }

    private func prepareSavedDismissSmokeUser(server: ServerState) -> UserState {
        let user = UserState(
            id: "debug-sign-in-dismiss-smoke-user",
            serverID: server.id,
            username: "debug-sign-in-dismiss-smoke"
        )

        _ = user.storeAccessToken("debug-sign-in-dismiss-smoke-token")

        var userData = UserDto()
        userData.id = user.id
        userData.name = user.username
        user.data = userData

        var users = StoredValues[.User.users]
        users.removeAll { $0.id == user.id }
        users.append(user)
        StoredValues[.User.users] = users

        var servers = StoredValues[.Server.servers]
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            let existingServer = servers[index]
            servers[index] = ServerState(
                urls: existingServer.urls,
                currentURL: existingServer.currentURL,
                name: existingServer.name,
                id: existingServer.id,
                userIDs: existingServer.userIDs.filter { $0 != user.id } + [user.id]
            )
            StoredValues[.Server.servers] = servers
        }

        return user
    }
}

@MainActor
private struct DebugAddServerUserCompleteSmokeView: View {

    @StateObject
    private var coordinator = NavigationCoordinator()
    @StateObject
    private var rootCoordinator = RootCoordinator()

    @State
    private var didReceiveAddUserNotification = false
    @State
    private var didStart = false
    @State
    private var status = "ADD_SERVER_USER_COMPLETE_SMOKE_START"

    var body: some View {
        NavigationInjectionView(coordinator: coordinator) {
            ZStack {
                EmbyAppBackgroundView()

                Text(status)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .onAppear(perform: startIfNeeded)
            .onNotification(.didAddServerUser) { user in
                didReceiveAddUserNotification = true
                NSLog("ADD_SERVER_USER_COMPLETE_SMOKE_NOTIFICATION user=%@", user.id ?? "nil")
            }
        }
        .environmentObject(rootCoordinator)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        coordinator.push(.addServerUser())

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))

            if coordinator.presentedSheet == nil, didReceiveAddUserNotification {
                status = "ADD_SERVER_USER_COMPLETE_SMOKE_PASS"
                NSLog("ADD_SERVER_USER_COMPLETE_SMOKE_PASS presentedSheet=nil notification=true")
            } else {
                status = "ADD_SERVER_USER_COMPLETE_SMOKE_FAIL"
                NSLog(
                    "ADD_SERVER_USER_COMPLETE_SMOKE_FAIL presentedSheet=%@ notification=%@",
                    coordinator.presentedSheet?.id ?? "nil",
                    didReceiveAddUserNotification ? "true" : "false"
                )
            }
        }
    }
}

private struct DebugSearchSmokeView: View {

    enum SmokeState {
        case loading
        case content(query: String, items: [BaseItemDto])
        case failed(String)
    }

    @State
    private var state: SmokeState = .loading

    private var query: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-EmbySearchSmokeQuery"),
              arguments.indices.contains(arguments.index(after: index))
        else {
            return "勇者"
        }

        return arguments[arguments.index(after: index)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch state {
                    case .loading:
                        ProgressView("SEARCH_SMOKE_LOADING")
                    case let .content(query, items):
                        Text("SEARCH_SMOKE_OK")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("query=\(query)")
                        Text("seriesCount=\(items.count)")
                        ForEach(items, id: \.unwrappedIDHashOrZero) { item in
                            Text(item.displayTitle)
                                .font(.body)
                        }
                    case let .failed(message):
                        Text("SEARCH_SMOKE_FAIL")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Search Smoke")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard case .loading = state else { return }

            do {
                try await EmbyStore.setupDataStack()

                guard let userSession = Container.shared.currentUserSession() else {
                    state = .failed("Missing current user session")
                    return
                }

                let items = try await SearchSeriesResolver(
                    userSession: userSession,
                    filters: .default
                )
                .search(query: query)

                NSLog(
                    "SEARCH_SMOKE_OK query=%@ seriesCount=%d names=%@",
                    query,
                    items.count,
                    items.map(\.displayTitle).joined(separator: " | ")
                )

                state = .content(query: query, items: items)
            } catch {
                NSLog("SEARCH_SMOKE_FAIL %@", error.localizedDescription)
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private extension [String] {

    func value(after argument: String) -> String? {
        guard let index = firstIndex(of: argument) else { return nil }
        let valueIndex = self.index(after: index)
        guard indices.contains(valueIndex) else { return nil }
        return self[valueIndex]
    }
}

@MainActor
private struct DebugNavigationDismissSmokeView: View {

    @StateObject
    private var coordinator = NavigationCoordinator()
    @StateObject
    private var rootCoordinator = RootCoordinator()

    @State
    private var didStart = false
    @State
    private var status = "NAV_DISMISS_SMOKE_START"

    var body: some View {
        NavigationInjectionView(coordinator: coordinator) {
            ZStack {
                EmbyAppBackgroundView()

                Text(status)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .onAppear(perform: startIfNeeded)
        }
        .environmentObject(rootCoordinator)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        coordinator.push(
            NavigationRoute(id: "debugNavigationDismissFullscreen", style: .fullscreen) {
                DebugNavigationDismissChildView()
            }
        )

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if coordinator.presentedFullScreen == nil {
                status = "NAV_DISMISS_SMOKE_PASS"
                NSLog("NAV_DISMISS_SMOKE_PASS presentedFullScreen=nil")
            } else {
                status = "NAV_DISMISS_SMOKE_FAIL"
                NSLog("NAV_DISMISS_SMOKE_FAIL presentedFullScreen=%@", coordinator.presentedFullScreen?.id ?? "unknown")
            }
        }
    }
}

private struct DebugNavigationDismissChildView: View {

    @Router
    private var router

    var body: some View {
        ZStack {
            EmbyAppBackgroundView()

            Text("NAV_DISMISS_SMOKE_CHILD")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                router.dismiss()
            }
        }
    }
}
#endif

extension UINavigationController {

    // Remove back button text
    override open func viewWillLayoutSubviews() {
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
}
