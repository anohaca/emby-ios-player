//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation
import SwiftUI
import UIKit

// TODO: seems to redraw view when popped to sometimes?
//       - similar to MediaView TODO bug?
//       - indicated by snapping to the top
struct HomeView: View {

    @Default(.Customization.nextUpPosterType)
    private var nextUpPosterType
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Home.sectionOrder)
    private var sectionOrder
    @Default(.Customization.Home.hiddenSectionIDs)
    private var hiddenSectionIDs
    @Default(.Customization.recentlyAddedPosterType)
    private var recentlyAddedPosterType

    @Router
    private var router

    @StateObject
    private var viewModel = HomeViewModel()
    @State
    private var isPullRefreshControlActive = false

    #if DEBUG
    private enum PlaybackExitLayoutSmoke {
        static var didRoute = false

        static var isRequested: Bool {
            ProcessInfo.processInfo.arguments.contains("-EmbyHomePlaybackExitLayoutSmoke")
        }
    }
    #endif

    private var homeBackground: some View {
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

    private var availableSections: [HomeSectionDescriptor] {
        let dynamicSections: [HomeSectionDescriptor] = viewModel.libraries.compactMap { libraryViewModel in
            guard let id = libraryViewModel.parent?.id else { return nil }

            return HomeSectionDescriptor.latestInLibrary(
                id: id,
                title: libraryViewModel.parent?.displayTitle ?? .emptyDash
            )
        }

        return HomeSectionDescriptor.standardSections + dynamicSections
    }

    private var visibleSections: [HomeSectionDescriptor] {
        let hiddenIDs = Set(hiddenSectionIDs)

        return HomeSectionDescriptor
            .ordered(availableSections, using: sectionOrder)
            .filter { section in
                guard !hiddenIDs.contains(section.id) else { return false }

                if section.id == HomeSectionDescriptor.recentlyAddedID {
                    return showRecentlyAdded
                }

                return true
            }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSectionDescriptor) -> some View {
        switch section.id {
        case HomeSectionDescriptor.continueWatchingID:
            ContinueWatchingView(viewModel: viewModel)
        case HomeSectionDescriptor.nextUpID:
            NextUpView(viewModel: viewModel.nextUpViewModel)
                .onSetPlayed { item in
                    viewModel.send(.setIsPlayed(true, item))
                }
        case HomeSectionDescriptor.recentlyAddedID:
            RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
        default:
            if let libraryID = HomeSectionDescriptor.latestInLibrarySourceID(from: section.id),
               let libraryViewModel = viewModel.libraries.first(where: { $0.parent?.id == libraryID })
            {
                LatestInLibraryView(viewModel: libraryViewModel)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleSections) { section in
                    sectionView(section)
                }
            }
            .edgePadding(.vertical)
        }
        .background(homeBackground)
        .homeRefreshControl(
            isRefreshing: viewModel.backgroundStates.contains(.refresh)
        ) {
            isPullRefreshControlActive = true
            viewModel.send(.refresh)
        }
    }

    var body: some View {
        ZStack {
            homeBackground

            switch viewModel.state {
            case .content:
                contentView
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .onFirstAppear {
            viewModel.send(.refresh)
        }
        .onAppear {
            viewModel.send(.applyUserDataOverrides)
            viewModel.send(.refreshIfPendingInvalidation)
        }
        .navigationTitle(L10n.home)
        .topBarTrailing {

            if viewModel.backgroundStates.contains(.refresh), !isPullRefreshControlActive {
                ProgressView()
            }

            SettingsBarButton(
                server: viewModel.userSession.server,
                user: viewModel.userSession.user
            ) {
                router.route(to: .settings)
            }
        }
        .sinceLastDisappear { interval in
            if interval > 60 ||
                viewModel.notificationsReceived.contains(.itemMetadataDidChange) ||
                viewModel.notificationsReceived.contains(.itemShouldRefreshMetadata) ||
                viewModel.notificationsReceived.contains(.resumeItemRecencyDidChange)
            {
                viewModel.send(.backgroundRefresh)
                viewModel.notificationsReceived.remove(.itemMetadataDidChange)
                viewModel.notificationsReceived.remove(.itemShouldRefreshMetadata)
                viewModel.notificationsReceived.remove(.resumeItemRecencyDidChange)
            }
        }
        .onChange(of: viewModel.backgroundStates.contains(.refresh)) { isRefreshing in
            guard !isRefreshing else { return }
            isPullRefreshControlActive = false
        }
        .onChange(of: hiddenSectionIDs) { _ in
            guard viewModel.state == .content else { return }
            viewModel.send(.backgroundRefresh)
        }
        #if DEBUG
        .task {
            await runPlaybackExitLayoutSmokeIfNeeded()
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private func runPlaybackExitLayoutSmokeIfNeeded() async {
        guard Self.PlaybackExitLayoutSmoke.isRequested,
              !Self.PlaybackExitLayoutSmoke.didRoute
        else { return }

        for _ in 0 ..< 40 {
            if routePlaybackExitLayoutSmokeIfPossible() {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        NSLog("EmbyHomePlaybackExitLayoutSmoke route=failed reason=no-resume-item")
    }

    @MainActor
    private func routePlaybackExitLayoutSmokeIfPossible() -> Bool {
        guard !Self.PlaybackExitLayoutSmoke.didRoute,
              case .content = viewModel.state,
              let item = viewModel.resumeItems.first
        else { return false }

        Self.PlaybackExitLayoutSmoke.didRoute = true
        let queue: (any MediaPlayerQueue)? = item.type == .episode
            ? EpisodeMediaPlayerQueue(episode: item)
            : nil

        NSLog(
            "EmbyHomePlaybackExitLayoutSmoke route=requested item=%@ title=%@",
            item.id ?? "<nil>",
            item.displayTitle
        )
        router.route(
            to: .videoPlayer(
                item: item,
                mediaSource: item.mediaSources?.first,
                queue: queue
            )
        )
        return true
    }
    #endif
}

private extension View {

    @MainActor
    func homeRefreshControl(
        isRefreshing: Bool,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeRefreshControlModifier(
                isRefreshing: isRefreshing,
                onRefresh: onRefresh
            )
        )
    }
}

private struct HomeRefreshControlModifier: ViewModifier {

    let isRefreshing: Bool
    let onRefresh: () -> Void

    @StateObject
    private var coordinator = HomeRefreshControlCoordinator()

    func body(content: Content) -> some View {
        content
            .introspect(
                .scrollView,
                on: .iOS(.v16, .v17, .v18, .v26),
                scope: .receiver
            ) { scrollView in
                coordinator.attach(to: scrollView, onRefresh: onRefresh)
                coordinator.update(isRefreshing: isRefreshing)
            }
            .onChange(of: isRefreshing) { newValue in
                coordinator.update(isRefreshing: newValue)
            }
    }
}

@MainActor
private final class HomeRefreshControlCoordinator: NSObject, ObservableObject {

    private let refreshControl = UIRefreshControl()
    private var isRefreshing = false
    private var onRefresh: (() -> Void)?

    override init() {
        super.init()

        refreshControl.addTarget(
            self,
            action: #selector(refreshControlValueChanged),
            for: .valueChanged
        )
    }

    func attach(to scrollView: UIScrollView, onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh

        scrollView.alwaysBounceVertical = true

        if scrollView.refreshControl !== refreshControl {
            scrollView.refreshControl = refreshControl
        }
    }

    func update(isRefreshing: Bool) {
        self.isRefreshing = isRefreshing

        guard !isRefreshing, refreshControl.isRefreshing else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRefreshing, self.refreshControl.isRefreshing else { return }
            self.refreshControl.endRefreshing()
        }
    }

    @objc
    private func refreshControlValueChanged() {
        onRefresh?()
    }
}
