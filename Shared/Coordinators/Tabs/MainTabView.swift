//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import SwiftUI

// TODO: move popup to router
//       - or, make tab view environment object

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    @State
    private var isVideoPlayerTransitionCoverVisible = false

    @State
    private var videoPlayerTransitionCoverTask: Task<Void, Never>?

    #if os(iOS)
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.favorites
        TabItem.search
        TabItem.media
    }
    #else
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.library(
            title: L10n.tvShowsCapitalized,
            systemName: "tv",
            filters: .init(itemTypes: [.series])
        )
        TabItem.library(
            title: L10n.movies,
            systemName: "film",
            filters: .init(itemTypes: [.movie])
        )
        TabItem.search
        TabItem.media
        TabItem.settings
    }
    #endif

    @ViewBuilder
    var body: some View {
        ZStack {
            TabView(selection: $tabCoordinator.selectedTabID) {
                ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                    NavigationInjectionView(
                        coordinator: tab.coordinator
                    ) {
                        tab.item.content
                    }
                    .environmentObject(tabCoordinator)
                    .environment(\.tabItemSelected, tab.publisher)
                    .tabItem {
                        Label(
                            tab.item.title,
                            systemImage: tab.item.systemImage
                        )
                        .labelStyle(tab.item.labelStyle)
                        .symbolRenderingMode(.monochrome)
                        .eraseToAnyView()
                    }
                    .tag(tab.item.id)
                }
            }
            .opacity(isVideoPlayerTransitionCoverVisible ? 0 : 1)

            if isVideoPlayerTransitionCoverVisible {
                videoPlayerTransitionBackground
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmbyAppBackgroundView())
        .onReceive(Notifications[.willPresentVideoPlayer].publisher) {
            videoPlayerTransitionCoverTask?.cancel()
            withDisabledAnimation {
                isVideoPlayerTransitionCoverVisible = true
            }
            #if DEBUG
            NSLog("EmbyMainTabTransitionCover visible=true")
            #endif
        }
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            videoPlayerTransitionCoverTask?.cancel()
            videoPlayerTransitionCoverTask = Task {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withDisabledAnimation {
                        isVideoPlayerTransitionCoverVisible = false
                    }
                    #if DEBUG
                    NSLog("EmbyMainTabTransitionCover visible=false")
                    #endif
                }
            }
        }
        .onDisappear {
            videoPlayerTransitionCoverTask?.cancel()
            videoPlayerTransitionCoverTask = nil
        }
    }

    private var videoPlayerTransitionBackground: some View {
        ZStack {
            EmbyAppBackgroundView()

            LinearGradient(
                stops: [
                    .init(color: Color.mediaContentBackground.opacity(0.94), location: 0),
                    .init(color: Color.mediaContentBackground.opacity(0.86), location: 0.48),
                    .init(color: Color.mediaContentBackground.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func withDisabledAnimation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }
}
