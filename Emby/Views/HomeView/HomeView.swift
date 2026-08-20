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

    private let destinationPickerHeight: CGFloat = 52
    private let destinationPageAnimation = Animation.interactiveSpring(
        response: 0.34,
        dampingFraction: 0.88
    )
    // Keep the destination swipe inside the shared picker/title strip so the
    // first poster row's horizontal scroll view never competes for the drag.
    private let destinationPageGestureActivationHeight: CGFloat = 68

    private enum HomeDestination: String, CaseIterable, Identifiable {
        case library = "首页"
        case weekly = "星期"

        var id: Self { self }
    }

    @Default(.Customization.nextUpPosterType)
    private var nextUpPosterType
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Home.showContinueWatching)
    private var showContinueWatching
    @Default(.Customization.Home.showLogButton)
    private var showHomeLogButton
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
    private var selectedDestination = HomeDestination.library
    @GestureState
    private var destinationPageDragOffset: CGFloat = 0
    @State
    private var libraryScrollOffset: CGFloat = 0
    @State
    private var weeklyScrollOffset: CGFloat = 0
    @State
    private var appliedWeeklyScheduleEnabled = Defaults[.Customization.Home.weeklyScheduleEnabled]
    @State
    private var appliedAniRSSURL = Defaults[.Customization.Home.aniRSSURL]
    @State
    private var pullRefreshRowResetRevision = 0
    @State
    private var homeHorizontalOffsetResetRevision = 0
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
    /// Suppresses data refreshes during navigation zoom transition
    /// so the matched-geometry source views stay stable.
    @State
    private var isInNavigationTransition = false
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
        EmbyAppBackgroundView()
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

                if section.id == HomeSectionDescriptor.continueWatchingID {
                    return showContinueWatching
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
        case HomeSectionDescriptor.resumeID:
            ContinueWatchingView(viewModel: viewModel, kind: .resume)
        case HomeSectionDescriptor.continueWatchingID:
            ContinueWatchingView(viewModel: viewModel, kind: .continueWatching)
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
            LazyVStack(alignment: .leading, spacing: 10) {
                if showsWeeklySchedule {
                    // Keep the first row below the overlaid picker without
                    // reducing the full-screen scroll view's viewport.
                    Color.clear
                        .frame(height: destinationPickerHeight)
                }

                ForEach(visibleSections) { section in
                    sectionView(section)
                        .id("\(section.id)-\(pullRefreshRowResetRevision)")
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
                    AppLog.event(
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
        .clearScrollViewBackground()
        #if DEBUG
        .background(HomeLayoutTraceView(name: "scroll-content", playerDismissTraceStart: playerDismissTraceStart))
        #endif
        .homeRefreshControl(
            isRefreshing: viewModel.backgroundStates.contains(.refresh),
            horizontalOffsetResetRevision: homeHorizontalOffsetResetRevision
        ) {
            handlePullRefresh()
        } onScrollOffsetChange: { offset in
            handleDestinationScrollOffset(offset, destination: .library)
        }
    }

    private var destinationPicker: some View {
        Picker("首页界面", selection: destinationSelection) {
            ForEach(HomeDestination.allCases) { destination in
                Text(destination.rawValue).tag(destination)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var activeDestinationScrollDelta: CGFloat {
        let offset: CGFloat
        switch selectedDestination {
        case .library:
            offset = libraryScrollOffset
        case .weekly:
            offset = weeklyScrollOffset
        }

        // ScrollViewOffsetCallbackModifier reports a normalized distance from
        // the actual top, so the top is always zero for both destinations.
        return max(0, offset)
    }

    private var sharedDestinationPicker: some View {
        let progress = min(1, activeDestinationScrollDelta / destinationPickerHeight)

        return destinationPicker
            // Keep the layout slot stable while the controls follow the active
            // scroll view continuously. This matches the original home page:
            // the bar moves away with the content instead of disappearing at a
            // threshold.
            .offset(y: -destinationPickerHeight * progress)
            .frame(height: destinationPickerHeight, alignment: .top)
            .clipped()
            .opacity(1 - progress)
            // Switching pages changes the active scroll offset as well. Animate
            // that one state change with the page transition, while ordinary
            // vertical scrolling remains directly driven by the live offset.
            .animation(destinationPageAnimation, value: selectedDestination)
    }

    private var sharedNavigationTitle: some View {
        let progress = min(1, activeDestinationScrollDelta / destinationPickerHeight)

        return ZStack {
            Text(L10n.home)
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                // The title and destination picker share the same collapse
                // distance. Keeping this travel identical prevents the large
                // title from disappearing at a different visual position
                // than the picker while switching between destinations.
                .offset(y: -38 - (destinationPickerHeight * progress))
                .opacity(1 - progress)
        }
        .frame(maxWidth: .infinity, maxHeight: destinationPickerHeight, alignment: .top)
        .allowsHitTesting(false)
        .animation(destinationPageAnimation, value: selectedDestination)
    }

    private var destinationSelection: Binding<HomeDestination> {
        Binding(
            get: { selectedDestination },
            // The page container owns the single transition animation. A
            // second animation here makes the two directions feel different.
            set: { selectedDestination = $0 }
        )
    }

    private var configuredAniRSSURL: URL? {
        let value = appliedAniRSSURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let normalized = value.contains("://") ? value : "http://\(value)"
        guard var components = URLComponents(string: normalized),
              components.host != nil
        else { return nil }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url
    }

    private var showsWeeklySchedule: Bool {
        return appliedWeeklyScheduleEnabled && configuredAniRSSURL != nil
    }

    @ViewBuilder
    private var libraryDestinationContent: some View {
        switch viewModel.state {
        case .content:
            contentView
        case let .error(error):
            ErrorView(error: error)
        case .initial, .refreshing:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var destinationPages: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                libraryDestinationContent
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let configuredAniRSSURL {
                    WeeklyScheduleView(
                        baseURL: configuredAniRSSURL,
                        topContentInset: destinationPickerHeight,
                        onScrollOffsetChange: { offset in
                            handleDestinationScrollOffset(offset, destination: .weekly)
                        }
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .offset(
                x: -CGFloat(selectedDestination == .weekly ? 1 : 0) * proxy.size.width + destinationPageDragOffset
            )
            .animation(destinationPageAnimation, value: selectedDestination)
            .contentShape(Rectangle())
            // Keep this simultaneous with the nested vertical/horizontal
            // scroll views. The start-area guard below prevents a poster's
            // own horizontal paging gesture from becoming a destination
            // switch, while the nested scroll view remains fully responsive.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .updating($destinationPageDragOffset) { value, state, _ in
                        guard value.startLocation.y <= destinationPageGestureActivationHeight,
                              abs(value.translation.width) > abs(value.translation.height),
                              (selectedDestination == .library && value.translation.width < 0) ||
                              (selectedDestination == .weekly && value.translation.width > 0)
                        else { return }
                        state = value.translation.width
                    }
                    .onEnded { value in
                        guard value.startLocation.y <= destinationPageGestureActivationHeight,
                              abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 60,
                              (selectedDestination == .library && value.translation.width < 0) ||
                              (selectedDestination == .weekly && value.translation.width > 0)
                        else { return }

                        withAnimation(destinationPageAnimation) {
                            if value.translation.width < 0 {
                                selectedDestination = .weekly
                            } else {
                                selectedDestination = .library
                            }
                        }
                    }
            )
        }
    }

    var body: some View {
        ZStack {
            homeBackground

            if showsWeeklySchedule {
                ZStack(alignment: .top) {
                    destinationPages

                    sharedNavigationTitle
                        .zIndex(2)

                    sharedDestinationPicker
                        .zIndex(1)
                }
            } else {
                libraryDestinationContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.homeTransitionLockedRowWidth, isHomeLayoutLockedForPlayer ? validHomeViewportSizeForPlayer.width : nil)
        .environment(\.homeRowResetRevision, pullRefreshRowResetRevision)
        .onChange(of: showsWeeklySchedule) { isEnabled in
            if !isEnabled {
                selectedDestination = .library
            }
            weeklyScrollOffset = 0
        }
        .onReceive(Notifications[.weeklyScheduleConfigurationDidChange].publisher) {
            appliedAniRSSURL = Defaults[.Customization.Home.aniRSSURL]
            appliedWeeklyScheduleEnabled = Defaults[.Customization.Home.weeklyScheduleEnabled]
        }
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
            AppLog.event(
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
            // Defer all data mutations until the zoom transition animation completes,
            // so the matched-geometry source views stay stable and don't jump.
            isInNavigationTransition = true
            resumeRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !isVideoPlayerPresented else { return }
                    isInNavigationTransition = false
                    viewModel.send(.applyUserDataOverrides)
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
        // Keep the native navigation bar in its large layout whenever the
        // destination picker is enabled. Its UIKit large/inline transition is
        // tied to whichever nested ScrollView was attached first and cannot
        // be kept in sync across the two pages. The shared title above uses
        // the active page's normalized scroll distance instead.
        .navigationTitle(showsWeeklySchedule ? "" : L10n.home)
        .backport.toolbarTitleDisplayMode(showsWeeklySchedule ? .large : .automatic)
        .toolbar {
            if showsWeeklySchedule {
                ToolbarItem(placement: .principal) {
                    Text(L10n.home)
                        .font(.headline.weight(.semibold))
                        .opacity(min(1, activeDestinationScrollDelta / destinationPickerHeight))
                        .animation(destinationPageAnimation, value: selectedDestination)
                }
            }
        }
        .topBarTrailing {

            if !isHomeToolbarHiddenForPlayerTransition {
                if viewModel.backgroundStates.contains(.refresh), !isPullRefreshControlActive {
                    ProgressView()
                }

                if showHomeLogButton {
                    Button {
                        router.route(to: .log)
                    } label: {
                        Image(systemName: "text.page")
                    }
                    .accessibilityLabel("查看日志")
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
            guard !isInNavigationTransition else { return }
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
            AppLog.event("EmbyHomeExitTrace refresh-state isRefreshing=%@", isRefreshing.description)
            #endif
            guard !isRefreshing else { return }
            isPullRefreshControlActive = false
        }
        #if DEBUG
        .onChange(of: viewModel.state) { state in
            AppLog.event("EmbyHomeExitTrace state-change state=%@", String(describing: state))
        }
        .onChange(of: visibleSections.map(\.id)) { sectionIDs in
            AppLog.event("EmbyHomeExitTrace sections-change ids=%@", sectionIDs.joined(separator: ","))
        }
        .onChange(of: viewModel.resumeItems.count) { count in
            AppLog.event("EmbyHomeExitTrace resume-count-change count=%d", count)
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
                isHomeSnapshotOverlayVisible = false
            }
            #if DEBUG
            AppLog.event(
                "EmbyHomeExitTrace layout-lock enabled width=%.1f height=%.1f current=%.1fx%.1f cover=false",
                lockedHomeViewportSize?.width ?? 0,
                lockedHomeViewportSize?.height ?? 0,
                homeViewportSize.width,
                homeViewportSize.height
            )
            #endif
        }
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            homeLayoutUnlockTask?.cancel()
            withDisabledHomeLayoutAnimation {
                isVideoPlayerPresented = false
                isHomeSnapshotOverlayVisible = false
            }
            #if DEBUG
            AppLog.event(
                "EmbyHomeExitTrace layout-lock cover-hidden-immediate stableSize=%.1fx%.1f orientation=%d",
                homeViewportSize.width,
                homeViewportSize.height,
                currentSceneOrientationRawValue
            )
            #endif
            homeLayoutUnlockTask = Task {
                await waitForStablePortraitHomeLayout()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withDisabledHomeLayoutAnimation {
                        isHomeLayoutLockedForPlayer = false
                        homeHorizontalOffsetResetRevision &+= 1
                    }
                    #if DEBUG
                    AppLog.event(
                        "EmbyHomeExitTrace layout-lock disabled-after-portrait stableSize=%.1fx%.1f orientation=%d",
                        homeViewportSize.width,
                        homeViewportSize.height,
                        currentSceneOrientationRawValue
                    )
                    #endif
                }
            }
        }
        #if DEBUG
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            playerDismissTraceStart = CACurrentMediaTime()
            AppLog.event("EmbyHomeExitTrace player-dismiss-start")
        }
        #endif
        #if DEBUG
        .task {
            await runPlaybackExitLayoutSmokeIfNeeded()
        }
        #endif
    }

    private func handlePullRefresh() {
        resumeRefreshTask?.cancel()
        resumeRefreshTask = nil
        isInNavigationTransition = false
        isPullRefreshControlActive = true
        pullRefreshRowResetRevision &+= 1
        viewModel.send(.setRefreshSuspended(false))
        viewModel.send(.refresh)
    }

    private func handleDestinationScrollOffset(_ offset: CGFloat, destination: HomeDestination) {
        switch destination {
        case .library:
            libraryScrollOffset = offset
        case .weekly:
            weeklyScrollOffset = offset
        }
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

        AppLog.event("EmbyHomePlaybackExitLayoutSmoke route=failed reason=no-resume-item")
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

        AppLog.event(
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
            AppLog.event("EmbyHomePlaybackExitLayoutSmoke close=requested")
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
            AppLog.event(
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
        horizontalOffsetResetRevision: Int,
        onRefresh: @escaping () -> Void,
        onScrollOffsetChange: @escaping (CGFloat) -> Void
    ) -> some View {
        modifier(
            HomeRefreshControlModifier(
                isRefreshing: isRefreshing,
                horizontalOffsetResetRevision: horizontalOffsetResetRevision,
                onRefresh: onRefresh,
                onScrollOffsetChange: onScrollOffsetChange
            )
        )
    }
}

private struct HomeRefreshControlModifier: ViewModifier {

    let isRefreshing: Bool
    let horizontalOffsetResetRevision: Int
    let onRefresh: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void

    @StateObject
    private var coordinator = HomeRefreshControlCoordinator()

    func body(content: Content) -> some View {
        content
            .introspect(
                .scrollView,
                on: .iOS(.v16, .v17, .v18, .v26),
                scope: .receiver
            ) { scrollView in
                coordinator.attach(
                    to: scrollView,
                    onRefresh: onRefresh,
                    onScrollOffsetChange: onScrollOffsetChange
                )
                coordinator.update(isRefreshing: isRefreshing)
            }
            .onChange(of: isRefreshing) { newValue in
                coordinator.update(isRefreshing: newValue)
            }
            .onChange(of: horizontalOffsetResetRevision) { _ in
                coordinator.restoreHorizontalPositionAfterPlayerDismissal()
            }
    }
}

@MainActor
private final class HomeRefreshControlCoordinator: NSObject, ObservableObject {

    private let refreshControl = UIRefreshControl()
    private var isRefreshing = false
    private var onRefresh: (() -> Void)?
    private var onScrollOffsetChange: ((CGFloat) -> Void)?
    private weak var scrollView: UIScrollView?
    private var observationContext = 0

    override init() {
        super.init()

        refreshControl.addTarget(
            self,
            action: #selector(refreshControlValueChanged),
            for: .valueChanged
        )
    }

    func attach(
        to scrollView: UIScrollView,
        onRefresh: @escaping () -> Void,
        onScrollOffsetChange: @escaping (CGFloat) -> Void
    ) {
        self.onRefresh = onRefresh
        self.onScrollOffsetChange = onScrollOffsetChange

        if self.scrollView !== scrollView {
            self.scrollView?.removeObserver(
                self,
                forKeyPath: #keyPath(UIScrollView.contentOffset),
                context: &observationContext
            )
            self.scrollView = scrollView
            scrollView.addObserver(
                self,
                forKeyPath: #keyPath(UIScrollView.contentOffset),
                options: [.initial, .new],
                context: &observationContext
            )
        }

        scrollView.alwaysBounceVertical = true

        if scrollView.refreshControl !== refreshControl {
            scrollView.refreshControl = refreshControl
        }
    }

    deinit {
        scrollView?.removeObserver(
            self,
            forKeyPath: #keyPath(UIScrollView.contentOffset),
            context: &observationContext
        )
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &observationContext,
              keyPath == #keyPath(UIScrollView.contentOffset),
              let scrollView = object as? UIScrollView
        else { return }

        let distanceFromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        onScrollOffsetChange?(max(0, distanceFromTop))
    }

    func update(isRefreshing: Bool) {
        self.isRefreshing = isRefreshing

        guard !isRefreshing, refreshControl.isRefreshing else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRefreshing, self.refreshControl.isRefreshing else { return }
            self.refreshControl.endRefreshing()
            self.restoreScrollPositionAfterRefreshIfNeeded()
        }
    }

    @objc
    private func refreshControlValueChanged() {
        onRefresh?()
    }

    private func restoreScrollPositionAfterRefreshIfNeeded() {
        guard let scrollView,
              !scrollView.isDragging,
              !scrollView.isDecelerating
        else { return }

        let topOffset = -scrollView.adjustedContentInset.top
        guard scrollView.contentOffset.y < topOffset else { return }

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: topOffset),
                animated: false
            )
        }
    }

    func restoreHorizontalPositionAfterPlayerDismissal() {
        restoreHorizontalPosition()

        DispatchQueue.main.async { [weak self] in
            self?.restoreHorizontalPosition()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.restoreHorizontalPosition()
        }
    }

    private func restoreHorizontalPosition() {
        guard let scrollView else { return }

        scrollView.layoutIfNeeded()
        let leadingOffset = -scrollView.adjustedContentInset.left
        guard abs(scrollView.contentOffset.x - leadingOffset) > 0.5 else { return }

        scrollView.setContentOffset(
            CGPoint(x: leadingOffset, y: scrollView.contentOffset.y),
            animated: false
        )

        #if DEBUG
        AppLog.event("EmbyHomeExitTrace horizontal-offset restored x=%.1f", leadingOffset)
        #endif
    }
}
