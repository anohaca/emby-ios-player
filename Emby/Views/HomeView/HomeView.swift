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
    @State
    private var resumeRefreshTask: Task<Void, Never>?
    @State
    private var homeViewportSize: CGSize = .zero
    @State
    private var homeSectionsStackSize: CGSize = .zero
    @State
    private var lastStableHomeSectionsStackHeight: CGFloat = 0
    @State
    private var expectedHomeSectionsStackHeightAfterPlayerDismiss: CGFloat = 0
    @State
    private var lockedHomeViewportSize: CGSize?
    @State
    private var isHomeLayoutLockedForPlayer = false
    @State
    private var isVideoPlayerPresented = false
    @State
    private var isHomeSnapshotOverlayVisible = false
    @State
    private var homeLayoutUnlockTask: Task<Void, Never>?
    #if DEBUG
    @State
    private var playerDismissTraceStart: CFTimeInterval?
    #endif

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

    private var validHomeViewportSizeForPlayer: CGSize {
        if let lockedHomeViewportSize,
           lockedHomeViewportSize.width >= 300,
           lockedHomeViewportSize.height >= lockedHomeViewportSize.width
        {
            return lockedHomeViewportSize
        }

        if homeViewportSize.width >= 300,
           homeViewportSize.height >= homeViewportSize.width
        {
            return homeViewportSize
        }

        let screenSize = UIScreen.main.bounds.size
        return CGSize(
            width: min(screenSize.width, screenSize.height),
            height: max(screenSize.width, screenSize.height)
        )
    }

    private var isHomeToolbarHiddenForPlayerTransition: Bool {
        isVideoPlayerPresented || isHomeLayoutLockedForPlayer || isHomeSnapshotOverlayVisible
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
                        #if DEBUG
                        .background(HomeLayoutTraceView(name: "section-\(section.id)", playerDismissTraceStart: playerDismissTraceStart))
                        #endif
                }
            }
            .edgePadding(.vertical)
            .onSizeChanged { size, _ in
                homeSectionsStackSize = size
                if isHomeSnapshotOverlayVisible,
                   !isHomeLayoutLockedForPlayer,
                   isPortraitHomeLayoutStable,
                   isRestoredHomeContentHeight(size.height)
                {
                    withDisabledHomeLayoutAnimation {
                        isHomeSnapshotOverlayVisible = false
                    }
                    #if DEBUG
                    NSLog(
                        "EmbyHomeExitTrace transition-cover hidden-by-layout sectionsHeight=%.1f expected=%.1f",
                        size.height,
                        expectedHomeSectionsStackHeightAfterPlayerDismiss
                    )
                    #endif
                }
                guard !isHomeLayoutLockedForPlayer,
                      !isHomeSnapshotOverlayVisible,
                      isPortraitHomeLayoutStable,
                      size.width >= 300,
                      size.height >= max(120, homeViewportSize.height * 0.5)
                else { return }
                lastStableHomeSectionsStackHeight = size.height
            }
            #if DEBUG
            .background(HomeLayoutTraceView(name: "sections-stack", playerDismissTraceStart: playerDismissTraceStart))
            #endif
        }
        .background(homeBackground)
        #if DEBUG
        .background(HomeLayoutTraceView(name: "scroll-content", playerDismissTraceStart: playerDismissTraceStart))
        #endif
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
                ZStack {
                    if !isHomeLayoutLockedForPlayer {
                        contentView
                            .frame(
                                width: nil,
                                height: nil,
                                alignment: .center
                            )
                            .opacity(isHomeSnapshotOverlayVisible ? 0 : 1)
                    }

                    if isHomeSnapshotOverlayVisible {
                        homeBackground
                    }
                }
                if isHomeLayoutLockedForPlayer,
                   !isHomeSnapshotOverlayVisible
                {
                    contentView
                        .frame(
                            width: lockedHomeViewportSize?.width,
                            height: lockedHomeViewportSize?.height,
                            alignment: .center
                        )
                }
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onSizeChanged { size, _ in
            homeViewportSize = size
            guard !isHomeLayoutLockedForPlayer,
                  size.width > 0,
                  size.height > 0,
                  size.width < size.height
            else { return }
            lockedHomeViewportSize = size
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .onFirstAppear {
            viewModel.send(.refresh)
        }
        .onAppear {
            #if DEBUG
            NSLog(
                "EmbyHomeExitTrace home-onAppear t=%.3f state=%@ sections=%d resume=%d libraries=%d refreshing=%@ orientation=%d",
                playerDismissTraceStart.map { CACurrentMediaTime() - $0 } ?? -1,
                String(describing: viewModel.state),
                visibleSections.count,
                viewModel.resumeItems.count,
                viewModel.libraries.count,
                viewModel.backgroundStates.contains(.refresh).description,
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.interfaceOrientation.rawValue ?? 0
            )
            #endif
            resumeRefreshTask?.cancel()
            viewModel.send(.applyUserDataOverrides)
            resumeRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !isVideoPlayerPresented else { return }
                    viewModel.send(.setRefreshSuspended(false))
                    viewModel.send(.refreshIfPendingInvalidation)
                }
            }
        }
        .onDisappear {
            resumeRefreshTask?.cancel()
            resumeRefreshTask = nil
            homeLayoutUnlockTask?.cancel()
            homeLayoutUnlockTask = nil
            viewModel.send(.setRefreshSuspended(true))
        }
        .navigationTitle(L10n.home)
        .topBarTrailing {

            if !isHomeToolbarHiddenForPlayerTransition {
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
            #if DEBUG
            NSLog("EmbyHomeExitTrace refresh-state isRefreshing=%@", isRefreshing.description)
            #endif
            guard !isRefreshing else { return }
            isPullRefreshControlActive = false
        }
        #if DEBUG
        .onChange(of: viewModel.state) { state in
            NSLog("EmbyHomeExitTrace state-change state=%@", String(describing: state))
        }
        .onChange(of: visibleSections.map(\.id)) { sectionIDs in
            NSLog("EmbyHomeExitTrace sections-change ids=%@", sectionIDs.joined(separator: ","))
        }
        .onChange(of: viewModel.resumeItems.count) { count in
            NSLog("EmbyHomeExitTrace resume-count-change count=%d", count)
        }
        #endif
        .onChange(of: hiddenSectionIDs) { _ in
            guard viewModel.state == .content else { return }
            viewModel.send(.backgroundRefresh)
        }
        .onReceive(Notifications[.willPresentVideoPlayer].publisher) {
            resumeRefreshTask?.cancel()
            resumeRefreshTask = nil
            homeLayoutUnlockTask?.cancel()
            homeLayoutUnlockTask = nil
            viewModel.send(.setRefreshSuspended(true))
            withDisabledHomeLayoutAnimation {
                isVideoPlayerPresented = true
                lockedHomeViewportSize = validHomeViewportSizeForPlayer
                expectedHomeSectionsStackHeightAfterPlayerDismiss = lastStableHomeSectionsStackHeight
                isHomeLayoutLockedForPlayer = true
                isHomeSnapshotOverlayVisible = true
            }
            #if DEBUG
            NSLog(
                "EmbyHomeExitTrace layout-lock enabled width=%.1f height=%.1f current=%.1fx%.1f cover=true",
                lockedHomeViewportSize?.width ?? 0,
                lockedHomeViewportSize?.height ?? 0,
                homeViewportSize.width,
                homeViewportSize.height
            )
            #endif
        }
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            homeLayoutUnlockTask?.cancel()
            homeLayoutUnlockTask = Task {
                await waitForStablePortraitHomeLayout()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withDisabledHomeLayoutAnimation {
                        isHomeLayoutLockedForPlayer = false
                        isVideoPlayerPresented = false
                    }
                    #if DEBUG
                    NSLog(
                        "EmbyHomeExitTrace layout-lock disabled stableSize=%.1fx%.1f orientation=%d",
                        homeViewportSize.width,
                        homeViewportSize.height,
                        currentSceneOrientationRawValue
                    )
                    #endif
                }
                await waitForRestoredHomeContentLayout()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard isHomeSnapshotOverlayVisible else { return }
                    withDisabledHomeLayoutAnimation {
                        isHomeSnapshotOverlayVisible = false
                    }
                    #if DEBUG
                    NSLog(
                        "EmbyHomeExitTrace transition-cover hidden sectionsHeight=%.1f expected=%.1f",
                        homeSectionsStackSize.height,
                        expectedHomeSectionsStackHeightAfterPlayerDismiss
                    )
                    #endif
                }
            }
        }
        #if DEBUG
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            playerDismissTraceStart = CACurrentMediaTime()
            NSLog("EmbyHomeExitTrace player-dismiss-start")
        }
        #endif
        #if DEBUG
        .task {
            await runPlaybackExitLayoutSmokeIfNeeded()
        }
        #endif
    }

    @MainActor
    private var currentSceneOrientationRawValue: Int {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation.rawValue ?? 0
    }

    @MainActor
    private var isPortraitHomeLayoutStable: Bool {
        currentSceneOrientationRawValue == UIInterfaceOrientation.portrait.rawValue &&
            homeViewportSize.width >= 300 &&
            homeViewportSize.height >= homeViewportSize.width
    }

    private func withDisabledHomeLayoutAnimation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func waitForStablePortraitHomeLayout() async {
        var stableTicks = 0

        for _ in 0 ..< 40 {
            guard !Task.isCancelled else { return }

            let isStable = await MainActor.run {
                isPortraitHomeLayoutStable
            }

            if isStable {
                stableTicks += 1
                if stableTicks >= 3 {
                    return
                }
            } else {
                stableTicks = 0
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func waitForRestoredHomeContentLayout() async {
        var stableTicks = 0

        for _ in 0 ..< 20 {
            guard !Task.isCancelled else { return }

            let isRestored = await MainActor.run {
                guard isHomeSnapshotOverlayVisible else { return true }
                guard isPortraitHomeLayoutStable else { return false }

                return isRestoredHomeContentHeight(homeSectionsStackSize.height)
            }

            if isRestored {
                stableTicks += 1
                if stableTicks >= 1 {
                    return
                }
            } else {
                stableTicks = 0
            }

            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    @MainActor
    private func isRestoredHomeContentHeight(_ height: CGFloat) -> Bool {
        let expectedHeight = expectedHomeSectionsStackHeightAfterPlayerDismiss
        if expectedHeight > 0 {
            return height >= expectedHeight * 0.8
        }

        let sectionCountMinimumHeight = CGFloat(max(1, visibleSections.count)) * 100
        return height >= max(120, homeViewportSize.height * 0.8, sectionCountMinimumHeight)
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
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            NSLog("EmbyHomePlaybackExitLayoutSmoke close=requested")
            NotificationCenter.default.post(name: .debugPlaybackSmokeCloseRequested, object: nil)
        }
        return true
    }
    #endif
}

#if DEBUG
private struct HomeLayoutTraceView: View {

    let name: String
    var playerDismissTraceStart: CFTimeInterval?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: HomeLayoutTraceSizePreferenceKey.self,
                    value: [name: proxy.size]
                )
        }
        .onPreferenceChange(HomeLayoutTraceSizePreferenceKey.self) { sizes in
            guard let size = sizes[name] else { return }
            NSLog(
                "EmbyHomeExitTrace layout t=%.3f name=%@ size=%.1fx%.1f orientation=%d",
                playerDismissTraceStart.map { CACurrentMediaTime() - $0 } ?? -1,
                name,
                size.width,
                size.height,
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.interfaceOrientation.rawValue ?? 0
            )
        }
    }
}

private struct HomeLayoutTraceSizePreferenceKey: PreferenceKey {

    static let defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif

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
