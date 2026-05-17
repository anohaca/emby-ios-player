//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG

import Defaults
import Darwin
import Factory
import Foundation
import Logging
import SwiftUI
import UIKit

struct DebugLoginSmokeView: View {

    @StateObject
    private var runner = DebugLoginSmokeRunner()

    var body: some View {
        VStack(spacing: 16) {
            Text(runner.state.title)
                .font(.title2.weight(.semibold))

            Text(runner.state.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
        .task {
            await runner.run()
        }
    }
}

struct DebugPlaybackSmokeView: View {

    @StateObject
    private var runner = DebugPlaybackSmokeRunner()

    @StateObject
    private var navigationCoordinator = NavigationCoordinator()

    @StateObject
    private var rootCoordinator = RootCoordinator()

    @State
    private var didRouteToPlayer = false

    @State
    private var didRouteToDetail = false

    @State
    private var didResetRouteAfterClose = false

    @State
    private var didReopenRouteAfterClose = false

    private var useRoute: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeUseRoute") || useDetailRoute
    }

    private var useDetailRoute: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeFromDetail")
    }

    private var detailRouteOnly: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeDetailOnly")
    }

    private var shouldResetRouteAfterClose: Bool {
        useRoute && (DebugPlaybackSmokeRunner.configuration?.closeAfterPass ?? false)
    }

    private var shouldReopenRouteAfterClose: Bool {
        useRoute && ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeReopenAfterClose")
    }

    private var reopenRouteAfterCloseDelayMilliseconds: Int {
        let value = ProcessInfo.processInfo.arguments
            .value(after: "-EmbyPlaybackSmokeReopenAfterCloseDelay")
            .flatMap(Double.init) ?? 0.6
        return max(100, Int((value * 1000).rounded()))
    }

    private var usesHomeBackground: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeHomeBackground")
    }

    private var usesLocalPlayback: Bool {
        DebugPlaybackSmokeRunner.configuration?.localFileURL != nil
    }

    private func routeIfNeeded(manager: MediaPlayerManager?) {
        guard useRoute else { return }

        if useDetailRoute, !didRouteToDetail, let item = runner.playbackItem {
            didRouteToDetail = true
            navigationCoordinator.push(.item(item: item))
            guard !detailRouteOnly, let manager else { return }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard !didRouteToPlayer else { return }
                didRouteToPlayer = true
                navigationCoordinator.push(.videoPlayer(manager: manager))
            }
            return
        }

        guard !detailRouteOnly, !didRouteToPlayer, let manager else { return }
        didRouteToPlayer = true
        navigationCoordinator.push(.videoPlayer(manager: manager))
    }

    private func resetRouteAfterSmokeClose() {
        guard shouldResetRouteAfterClose, !didResetRouteAfterClose else { return }
        didResetRouteAfterClose = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.2)) {
                navigationCoordinator.presentedFullScreen = nil
                navigationCoordinator.presentedNativeFullScreen = nil
                navigationCoordinator.presentedSheet = nil
                navigationCoordinator.path.removeAll()
            }
        }
    }

    private func reopenRouteAfterSmokeClose() {
        guard shouldReopenRouteAfterClose,
              !didReopenRouteAfterClose,
              let manager = runner.manager
        else { return }

        didReopenRouteAfterClose = true
        let delayMilliseconds = reopenRouteAfterCloseDelayMilliseconds

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            if navigationCoordinator.presentedFullScreen != nil {
                navigationCoordinator.presentedFullScreen = nil
                try? await Task.sleep(for: .milliseconds(100))
            }
            if navigationCoordinator.presentedNativeFullScreen != nil {
                navigationCoordinator.presentedNativeFullScreen = nil
                try? await Task.sleep(for: .milliseconds(100))
            }

            let reopenManager = runner.makeFreshLocalPlaybackManagerForSmoke() ?? manager
            didRouteToPlayer = false
            NSLog("PLAYBACK_SMOKE_REOPEN_ROUTE_AFTER_CLOSE delayMs=%d", delayMilliseconds)
            navigationCoordinator.push(.videoPlayer(manager: reopenManager))
        }
    }

    var body: some View {
        NavigationInjectionView(coordinator: navigationCoordinator) {
            smokeBody
        }
        .environmentObject(rootCoordinator)
        .onReceive(NotificationCenter.default.publisher(for: .debugPlaybackSmokeCloseRequested)) { _ in
            resetRouteAfterSmokeClose()
            reopenRouteAfterSmokeClose()
        }
    }

    private var smokeBody: some View {
        ZStack(alignment: .topLeading) {
            if let manager = runner.manager, !useRoute {
                VideoPlayerViewShim(manager: manager)
                    .overlay(alignment: .topLeading) {
                        if runner.state.shouldShowOverlay || manager.error != nil {
                            DebugPlaybackSmokeOverlay(runner: runner, manager: manager)
                        }
                    }
            } else if usesHomeBackground {
                if usesLocalPlayback {
                    DebugPlaybackSmokeHomeBackgroundView()
                } else {
                    MainTabView()
                }
            } else {
                Color.black
                    .overlay {
                        VStack(spacing: 14) {
                            Text(runner.state.title)
                                .font(.title2.weight(.semibold))

                            Text(runner.state.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .foregroundStyle(.white)
                    }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            if useRoute, runner.state.isTerminal || didResetRouteAfterClose {
                DebugPlaybackSmokeStatusOverlay(runner: runner)
            }
        }
        .task {
            await runner.run()
        }
        .onChange(of: runner.playbackItem?.id) { _ in
            guard detailRouteOnly else { return }
            routeIfNeeded(manager: runner.manager)
        }
        .onChange(of: runner.manager != nil) { hasManager in
            guard hasManager else { return }
            routeIfNeeded(manager: runner.manager)
        }
    }
}

private struct DebugPlaybackSmokeHomeBackgroundView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            EmbyAppBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("首页")
                        .font(.largeTitle.weight(.semibold))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("继续观看")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .frame(height: 120)
                            .overlay(alignment: .bottomLeading) {
                                Text("风之圣痕 S01E01")
                                    .font(.headline)
                                    .padding(14)
                            }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近新增")
                            .font(.headline)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(0 ..< 9, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(index.isMultiple(of: 2) ? 0.12 : 0.08))
                                    .aspectRatio(0.68, contentMode: .fit)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 72)
                .padding(.bottom, 120)
            }
        }
        .foregroundStyle(.white)
    }
}

struct DebugSubtitleAdjustmentSmokeView: View {
    var body: some View {
        DebugSubtitleAdjustmentSmokeRepresentable()
            .ignoresSafeArea()
            .background(Color.black)
            .statusBarHidden(true)
    }
}

struct DebugSubtitleLanguageSmokeView: View {

    @State
    private var status = "SUBTITLE_LANGUAGE_SMOKE_RUNNING"

    var body: some View {
        Text(status)
            .font(.headline.monospaced())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task {
                run()
            }
    }

    @MainActor
    private func run() {
        let traditionalByTitle = makeSubtitleStream(index: 2, language: nil, displayTitle: "繁體中文", title: "繁中")
        let english = makeSubtitleStream(index: 1, language: "eng", displayTitle: "English", title: "English")
        let traditionalByCode = makeSubtitleStream(index: 3, language: "zh-Hant", displayTitle: nil, title: nil)

        let selectedByTitle = MediaTrackLanguagePreference.automaticSubtitleStream(in: [english, traditionalByTitle])
        let selectedByCode = MediaTrackLanguagePreference.automaticSubtitleStream(in: [english, traditionalByCode])
        let chineseMatchesTraditionalTitle = MediaTrackLanguagePreference.chinese.matches(traditionalByTitle)
        let passed = selectedByTitle?.index == traditionalByTitle.index &&
            selectedByCode?.index == traditionalByCode.index &&
            chineseMatchesTraditionalTitle

        status = passed ? "SUBTITLE_LANGUAGE_SMOKE_PASS" : "SUBTITLE_LANGUAGE_SMOKE_FAIL"
        NSLog(
            "EmbySubtitleLanguageSmoke passed=%@ titleSelected=%d codeSelected=%d titleMatches=%@",
            passed.description,
            selectedByTitle?.index ?? -1,
            selectedByCode?.index ?? -1,
            chineseMatchesTraditionalTitle.description
        )
        precondition(passed, "Traditional Chinese subtitle auto-selection failed")
    }

    private func makeSubtitleStream(index: Int, language: String?, displayTitle: String?, title: String?) -> MediaStream {
        var stream = MediaStream()
        stream.index = index
        stream.language = language
        stream.displayTitle = displayTitle
        stream.title = title
        stream.isForced = false
        stream.isHearingImpaired = false
        return stream
    }
}

struct DebugSelectUserInitialServerSmokeView: View {

    @State
    private var status = "SELECT_USER_INITIAL_SERVER_SMOKE_RUNNING"

    var body: some View {
        Text(status)
            .font(.headline.monospaced())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task {
                await run()
            }
    }

    @MainActor
    private func run() async {
        do {
            try await EmbyStore.setupDataStack()

            let originalServers = StoredValues[.Server.servers]
            let originalUsers = StoredValues[.User.users]
            defer {
                StoredValues[.Server.servers] = originalServers
                StoredValues[.User.users] = originalUsers
            }

            let url = URL(string: "http://127.0.0.1:8096")!
            let server = ServerState(
                urls: [url],
                currentURL: url,
                name: "Initial Server Smoke",
                id: "initial-server-smoke",
                userIDs: []
            )
            StoredValues[.Server.servers] = [server]
            StoredValues[.User.users] = []

            let viewModel = SelectUserViewModel()
            let passed = viewModel.hasLoadedServers &&
                viewModel.servers.keys.contains { $0.id == server.id }

            status = passed ? "SELECT_USER_INITIAL_SERVER_SMOKE_PASS" : "SELECT_USER_INITIAL_SERVER_SMOKE_FAIL"
            NSLog(
                "EmbySelectUserInitialServerSmoke passed=%@ hasLoadedServers=%@ serverCount=%ld",
                passed.description,
                viewModel.hasLoadedServers.description,
                viewModel.servers.count
            )
            precondition(passed, "Select user initial server load failed")
        } catch {
            status = "SELECT_USER_INITIAL_SERVER_SMOKE_FAIL \(error.localizedDescription)"
            NSLog("EmbySelectUserInitialServerSmoke failed error=%@", error.localizedDescription)
            preconditionFailure("Select user initial server smoke failed: \(error.localizedDescription)")
        }
    }
}

struct DebugPlayerLocalizationSmokeView: View {
    var body: some View {
        DebugPlayerLocalizationSmokeRepresentable()
            .ignoresSafeArea()
            .background(Color.black)
            .statusBarHidden(true)
    }
}

private struct DebugPlayerLocalizationSmokeRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let arguments = ProcessInfo.processInfo.arguments
        let container = UIView()
        container.backgroundColor = .black

        let controlsView = PlayerControlsView()
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.backgroundColor = .black
        controlsView.updateTitle("播放器汉化", subtitle: "亮度 / 音量 / 字幕名称")
        controlsView.update(time: 62, duration: 24 * 60)
        controlsView.setPaused(true)
        controlsView.updateEpisodeNavigation(canGoPrevious: true, canGoNext: true)
        controlsView.applyEmbyPlaybackChrome()

        let jumpBackwardSeconds = arguments.value(after: "-EmbyPlayerJumpBackwardSeconds").flatMap(Int.init) ?? 10
        let jumpForwardSeconds = arguments.value(after: "-EmbyPlayerJumpForwardSeconds").flatMap(Int.init) ?? 10
        controlsView.updateJumpIntervals(
            backward: MediaJumpInterval(rawValue: .seconds(jumpBackwardSeconds)),
            forward: MediaJumpInterval(rawValue: .seconds(jumpForwardSeconds))
        )

        let subtitleTracks = [
            MPVSubtitleTrack(id: "1", title: "External Subtitle · ASS · CHS", isSelected: true),
            MPVSubtitleTrack(id: "2", title: "SRT · ENG", isSelected: false),
            MPVSubtitleTrack(id: "3", title: "Forced · Japanese", isSelected: false),
        ]
        controlsView.updateSubtitleTracks(subtitleTracks, selectedID: "1")
        controlsView.setControlsHidden(false, animated: false)

        let showsVolume = arguments.contains("-EmbyPlayerLocalizationSmokeVolume")
        controlsView.setGestureHUD(symbol: showsVolume ? "speaker.wave.2.fill" : "sun.max.fill",
                                   text: showsVolume ? "音量 50%" : "亮度 50%",
                                   visible: true)

        container.addSubview(controlsView)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: container.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let localizedTitles = subtitleTracks.map { PlayerControlsView.localizedSubtitleTrackTitleForSmoke($0.title) }
        let expectedTitles = ["外部字幕 · ASS · 简体中文", "SRT · 英语", "强制 · 日语"]
        let subtitleMenuTitles = controlsView.subtitleMenuTitlesForSmoke
        let settingsMenuTitles = controlsView.settingsMenuTitlesForSmoke
        let transportControlLabels = controlsView.transportControlLabelsForSmoke
        let subtitleButtonIndex = transportControlLabels.firstIndex(of: "字幕")
        let speedButtonIndex = transportControlLabels.firstIndex(of: "播放速度")
        let hasSubtitleAndSpeedTogether = subtitleButtonIndex != nil &&
            speedButtonIndex == subtitleButtonIndex.map { $0 + 1 }
        let expectedSubtitleMenuTitles = ["字幕"] + expectedTitles + ["打开字幕文件...", "关闭字幕"]
        let hasSubtitleActionsAtBottom = subtitleMenuTitles == expectedSubtitleMenuTitles
        let settingsRootMenuTitles = controlsView.settingsMenuRootChildTitlesForSmoke
        let hasSubtitleSettingsSubmenu = settingsRootMenuTitles == ["字幕设置"]
        let passed = localizedTitles == expectedTitles &&
            !subtitleMenuTitles.contains("调整位置/大小/轮廓") &&
            hasSubtitleActionsAtBottom &&
            hasSubtitleSettingsSubmenu &&
            settingsMenuTitles.contains("设置") &&
            settingsMenuTitles.contains("字幕设置") &&
            settingsMenuTitles.contains("调整字幕位置") &&
            settingsMenuTitles.contains("调整字幕大小") &&
            settingsMenuTitles.contains("调整字幕轮廓") &&
            !settingsMenuTitles.contains("调整位置/大小/轮廓") &&
            hasSubtitleAndSpeedTogether

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .left
        label.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.text = """
        字幕菜单
        \(localizedTitles.joined(separator: "\n"))
        打开字幕文件...
        关闭字幕
        设置菜单
        设置 > 字幕设置
        调整字幕位置 / 调整字幕大小 / 调整字幕轮廓
        \(passed ? "PASS" : "FAIL")
        """
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 86),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
        ])

        NSLog("EmbyPlayerLocalizationSmoke hud=%@ subtitles=%@ passed=%@",
              showsVolume ? "音量 50%" : "亮度 50%",
              (localizedTitles + ["subtitleMenu=\(subtitleMenuTitles.joined(separator: " | "))",
                                  "settingsMenu=\(settingsMenuTitles.joined(separator: " | "))",
                                  "settingsRoot=\(settingsRootMenuTitles.joined(separator: " | "))",
                                  "transport=\(transportControlLabels.joined(separator: " | "))"]).joined(separator: " | "),
              passed.description)
        precondition(passed, "Player localization smoke failed")

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct DebugSubtitleAdjustmentSmokeRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerControlsView {
        let controlsView = PlayerControlsView()
        let arguments = ProcessInfo.processInfo.arguments
        Defaults[.VideoPlayer.Subtitle.subtitlePosition] = 72
        Defaults[.VideoPlayer.Subtitle.subtitleScale] = 1.4
        Defaults[.VideoPlayer.Subtitle.subtitleBorderSize] = 3.5
        let storedSubtitlePosition = Defaults[.VideoPlayer.Subtitle.subtitlePosition]
        let storedSubtitleScale = Defaults[.VideoPlayer.Subtitle.subtitleScale]
        let storedSubtitleBorderSize = Defaults[.VideoPlayer.Subtitle.subtitleBorderSize]
        controlsView.backgroundColor = .black
        controlsView.updateTitle("Subtitle Adjustment", subtitle: "Position / Size / Border")
        controlsView.update(time: 62, duration: 24 * 60)
        controlsView.setPaused(true)
        controlsView.updateEpisodeNavigation(canGoPrevious: true, canGoNext: true)
        controlsView.updateSubtitleTracks([
            MPVSubtitleTrack(id: "1", title: "ASS · CHS", isSelected: true),
            MPVSubtitleTrack(id: "2", title: "SRT · ENG", isSelected: false),
        ], selectedID: "1")
        controlsView.updateSubtitleAdjustment(
            position: storedSubtitlePosition,
            scale: storedSubtitleScale,
            borderSize: storedSubtitleBorderSize
        )
        if arguments.contains("-EmbySubtitleAdjustmentSmokeSeparated") {
            addSeparatedSubtitleAdjustmentSmokeStatus(to: controlsView)
        }
        if arguments.contains("-EmbySubtitleAdjustmentSmokeScale") {
            controlsView.setSubtitleAdjustmentModeForSmoke(.scale)
        }
        if arguments.contains("-EmbySubtitleAdjustmentSmokeBorder") {
            controlsView.setSubtitleAdjustmentModeForSmoke(.border)
        }
        controlsView.setControlsHidden(false, animated: false)
        if arguments.contains("-EmbySubtitleAdjustmentSmokeExitState") {
            controlsView.onSubtitleAdjustmentVisibilityChanged = { [weak controlsView] _ in
                controlsView?.setControlsHidden(true, animated: false)
            }
            controlsView.onSubtitleAdjustmentEnded = { [weak controlsView] in
                controlsView?.setControlsHidden(true, animated: false)
            }
            controlsView.setSubtitleAdjustmentPanelVisible(true, animated: false)
            controlsView.onSubtitleAdjustmentEnded?()
            controlsView.setSubtitleAdjustmentPanelVisible(false, animated: false)
            addSubtitleAdjustmentSmokeStatus(to: controlsView)
        } else {
            controlsView.setSubtitleAdjustmentPanelVisible(true, animated: false)
            controlsView.setControlsHidden(true, animated: false)
        }
        return controlsView
    }

    func updateUIView(_ uiView: PlayerControlsView, context: Context) {}

    private func addSubtitleAdjustmentSmokeStatus(to controlsView: PlayerControlsView) {
        let keptHiddenAfterExit = !controlsView.controlsVisibleForSmoke && !controlsView.subtitleAdjustmentPanelVisibleForSmoke
        controlsView.setControlsHidden(false, animated: false)
        let canShowMainControlsAfterExit = controlsView.controlsVisibleForSmoke
        let passed = keptHiddenAfterExit && canShowMainControlsAfterExit
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = passed ? "PASS exit hidden; next tap shows UI" : "FAIL subtitle exit state"
        label.textColor = passed ? .systemGreen : .systemRed
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        controlsView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            label.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 72),
            label.widthAnchor.constraint(lessThanOrEqualTo: controlsView.safeAreaLayoutGuide.widthAnchor, constant: -32),
            label.heightAnchor.constraint(equalToConstant: 36),
        ])
        NSLog("EmbySubtitleAdjustmentSmokeExitState passed=%@ keptHiddenAfterExit=%@ canShowMainControlsAfterExit=%@ panelVisible=%@",
              passed.description,
              keptHiddenAfterExit.description,
              canShowMainControlsAfterExit.description,
              controlsView.subtitleAdjustmentPanelVisibleForSmoke.description)
        precondition(passed, "Subtitle adjustment exit state is incorrect")
    }

    private func addSeparatedSubtitleAdjustmentSmokeStatus(to controlsView: PlayerControlsView) {
        let menuTitles = controlsView.settingsMenuTitlesForSmoke
        let rootMenuTitles = controlsView.settingsMenuRootChildTitlesForSmoke
        let menuSeparated = menuTitles.contains("调整字幕位置") &&
            menuTitles.contains("调整字幕大小") &&
            menuTitles.contains("调整字幕轮廓") &&
            !menuTitles.contains("调整位置/大小/轮廓") &&
            rootMenuTitles == ["字幕设置"]

        controlsView.showSubtitleAdjustmentPanelForSmoke(.position)
        var lastPosition: Double?
        controlsView.onSubtitlePositionChanged = { position in
            lastPosition = position
        }
        let positionStepLabels = controlsView.subtitleAdjustmentStepButtonLabelsForSmoke == ["增加字幕位置", "减少字幕位置"]
        controlsView.triggerSubtitleAdjustmentIncreaseForSmoke()
        let positionIncremented = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 29) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "29" &&
            abs((lastPosition ?? -1) - 71) < 0.01
        controlsView.triggerSubtitleAdjustmentDecreaseForSmoke()
        let positionRestored = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 28) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "28" &&
            abs((lastPosition ?? -1) - 72) < 0.01
        let positionSeparated = controlsView.subtitleAdjustmentModeForSmoke == .position &&
            abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 28) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "28" &&
            controlsView.subtitleAdjustmentValueFieldIsTopForSmoke &&
            controlsView.subtitleAdjustmentIconLabelForSmoke == "字幕位置" &&
            positionStepLabels &&
            positionIncremented &&
            positionRestored

        controlsView.showSubtitleAdjustmentPanelForSmoke(.scale)
        lastPosition = nil
        let scaleStepLabels = controlsView.subtitleAdjustmentStepButtonLabelsForSmoke == ["增加字幕大小", "减少字幕大小"]
        controlsView.triggerSubtitleAdjustmentIncreaseForSmoke()
        let scaleIncremented = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 1.41) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "1.41"
        controlsView.triggerSubtitleAdjustmentDecreaseForSmoke()
        let scaleRestored = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 1.4) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "1.4"
        let scaleKeptPositionCallbackSeparated = lastPosition == nil
        let scaleSeparated = controlsView.subtitleAdjustmentModeForSmoke == .scale &&
            abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 1.4) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "1.4" &&
            controlsView.subtitleAdjustmentValueFieldIsTopForSmoke &&
            controlsView.subtitleAdjustmentIconLabelForSmoke == "字幕大小" &&
            scaleStepLabels &&
            scaleIncremented &&
            scaleRestored &&
            scaleKeptPositionCallbackSeparated

        controlsView.showSubtitleAdjustmentPanelForSmoke(.border)
        lastPosition = nil
        let borderStepLabels = controlsView.subtitleAdjustmentStepButtonLabelsForSmoke == ["增加字幕轮廓宽度", "减少字幕轮廓宽度"]
        controlsView.triggerSubtitleAdjustmentIncreaseForSmoke()
        let borderIncremented = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 3.6) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "3.6"
        controlsView.triggerSubtitleAdjustmentDecreaseForSmoke()
        let borderRestored = abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 3.5) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "3.5"
        let borderKeptPositionCallbackSeparated = lastPosition == nil
        let borderSeparated = controlsView.subtitleAdjustmentModeForSmoke == .border &&
            abs(controlsView.subtitleAdjustmentSliderValueForSmoke - 3.5) < 0.01 &&
            controlsView.subtitleAdjustmentInputTextForSmoke == "3.5" &&
            controlsView.subtitleAdjustmentValueFieldIsTopForSmoke &&
            controlsView.subtitleAdjustmentIconLabelForSmoke == "字幕轮廓宽度" &&
            borderStepLabels &&
            borderIncremented &&
            borderRestored &&
            borderKeptPositionCallbackSeparated

        let passed = menuSeparated && positionSeparated && scaleSeparated && borderSeparated
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = passed ? "PASS separated subtitle adjustments" : "FAIL separated subtitle adjustments"
        label.textColor = passed ? .systemGreen : .systemRed
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        controlsView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            label.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 72),
            label.widthAnchor.constraint(lessThanOrEqualTo: controlsView.safeAreaLayoutGuide.widthAnchor, constant: -32),
            label.heightAnchor.constraint(equalToConstant: 36),
        ])
        NSLog("EmbySubtitleAdjustmentSmokeSeparated passed=%@ menu=%@ position=%@ scale=%@ border=%@",
              passed.description,
              "\(menuTitles.joined(separator: " | ")) root=\(rootMenuTitles.joined(separator: " | "))",
              positionSeparated.description,
              scaleSeparated.description,
              borderSeparated.description)
        precondition(passed, "Subtitle adjustment controls are not separated")
    }
}

extension Notification.Name {
    static let debugPlaybackSmokeCloseRequested = Notification.Name("debugPlaybackSmokeCloseRequested")
    static let debugPlaybackSmokeNextRequested = Notification.Name("debugPlaybackSmokeNextRequested")
    static let debugPlaybackSmokePreviousRequested = Notification.Name("debugPlaybackSmokePreviousRequested")
    static let debugPlaybackSmokeVerifyLongPressHUDRequested = Notification.Name("debugPlaybackSmokeVerifyLongPressHUDRequested")
    static let debugPlaybackSmokeLongPressHUDVerified = Notification.Name("debugPlaybackSmokeLongPressHUDVerified")
    static let debugPlaybackSmokeVerifyProgressBarAutoHideRequested = Notification.Name("debugPlaybackSmokeVerifyProgressBarAutoHideRequested")
    static let debugPlaybackSmokeProgressBarAutoHideVerified = Notification.Name("debugPlaybackSmokeProgressBarAutoHideVerified")
    static let debugPlaybackSmokeVerifySeekGestureHUDRequested = Notification.Name("debugPlaybackSmokeVerifySeekGestureHUDRequested")
    static let debugPlaybackSmokeSeekGestureHUDVerified = Notification.Name("debugPlaybackSmokeSeekGestureHUDVerified")
}

@MainActor
final class DebugPlaybackSmokeRunner: ObservableObject {

    struct Configuration {
        let localFileURL: URL?
        let serverURL: URL?
        let username: String?
        let password: String?
        let titleFilter: String?
        let itemID: String?
        let mpvLogLevel: String
        let useSavedSession: Bool
        let closeAfterPass: Bool
        let useRoute: Bool
        let useDetailRoute: Bool
        let useFirstResumeItem: Bool
        let verifyAdjacentNavigation: Bool
        let useControlsNavigation: Bool
        let verifyLongPressGestureHUD: Bool
        let verifyProgressBarAutoHide: Bool
        let verifySeekGestureHUD: Bool
        let verifyResumeRetainedAfterClose: Bool
        let requireEmbeddedTextSubtitle: Bool
        let forceCloseAfterSeconds: Double?
    }

    enum State {
        case running(String)
        case passed(String)
        case failed(String)

        var title: String {
            switch self {
            case .running:
                "PLAYBACK_SMOKE_RUNNING"
            case .passed:
                "PLAYBACK_SMOKE_PASS"
            case .failed:
                "PLAYBACK_SMOKE_FAIL"
            }
        }

        var detail: String {
            switch self {
            case let .running(detail), let .passed(detail), let .failed(detail):
                detail
            }
        }

        var shouldShowOverlay: Bool {
            switch self {
            case .running, .failed:
                true
            case .passed:
                false
            }
        }

        var isTerminal: Bool {
            switch self {
            case .passed, .failed:
                true
            case .running:
                false
            }
        }
    }

    @Published
    var state: State = .running("Preparing playback smoke test")

    @Published
    var manager: MediaPlayerManager?

    @Published
    var playbackItem: BaseItemDto?

    private let logger = Logger.emby()
    private var hasRun = false
    private var hasScheduledForceClose = false

    private static var detailRouteOnlyRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeDetailOnly")
    }

    static var configuration: Configuration? {
        let arguments = ProcessInfo.processInfo.arguments
        let titleFilter = arguments.value(after: "-EmbyPlaybackSmokeTitle")
        let itemID = arguments.value(after: "-EmbyPlaybackSmokeItemID")
        let forceCloseAfterSeconds = arguments.value(after: "-EmbyPlaybackSmokeForceCloseAfter").flatMap(Double.init)
        let defaultLogLevel = titleFilter == nil && itemID == nil ? "warn" : "info"
        let localFileURL: URL? = {
            if let path = arguments.value(after: "-EmbyPlaybackSmokeLocalFile") {
                return URL(fileURLWithPath: path)
            }

            if let bundleName = arguments.value(after: "-EmbyPlaybackSmokeBundleFile") {
                let url = URL(fileURLWithPath: bundleName)
                let resourceName = url.deletingPathExtension().path
                let resourceExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
                return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
            }

            return nil
        }()

        if let localFileURL {
            return Configuration(
                localFileURL: localFileURL,
                serverURL: nil,
                username: nil,
                password: nil,
                titleFilter: titleFilter,
                itemID: itemID,
                mpvLogLevel: arguments.value(after: "-EmbyPlaybackSmokeMPVLogLevel") ?? defaultLogLevel,
                useSavedSession: false,
                closeAfterPass: arguments.contains("-EmbyPlaybackSmokeCloseAfterPass"),
                useRoute: arguments.contains("-EmbyPlaybackSmokeUseRoute"),
                useDetailRoute: arguments.contains("-EmbyPlaybackSmokeFromDetail"),
                useFirstResumeItem: false,
                verifyAdjacentNavigation: false,
                useControlsNavigation: false,
                verifyLongPressGestureHUD: false,
                verifyProgressBarAutoHide: false,
                verifySeekGestureHUD: false,
                verifyResumeRetainedAfterClose: false,
                requireEmbeddedTextSubtitle: false,
                forceCloseAfterSeconds: forceCloseAfterSeconds
            )
        }

        if arguments.contains("-EmbyPlaybackSmokeUseSavedSession") {
            return Configuration(
                localFileURL: nil,
                serverURL: nil,
                username: nil,
                password: nil,
                titleFilter: titleFilter,
                itemID: itemID,
                mpvLogLevel: arguments.value(after: "-EmbyPlaybackSmokeMPVLogLevel") ?? defaultLogLevel,
                useSavedSession: true,
                closeAfterPass: arguments.contains("-EmbyPlaybackSmokeCloseAfterPass"),
                useRoute: arguments.contains("-EmbyPlaybackSmokeUseRoute"),
                useDetailRoute: arguments.contains("-EmbyPlaybackSmokeFromDetail"),
                useFirstResumeItem: arguments.contains("-EmbyPlaybackSmokeUseFirstResumeItem"),
                verifyAdjacentNavigation: arguments.contains("-EmbyPlaybackSmokeVerifyAdjacentNavigation"),
                useControlsNavigation: arguments.contains("-EmbyPlaybackSmokeUseControlsNavigation"),
                verifyLongPressGestureHUD: arguments.contains("-EmbyPlaybackSmokeVerifyLongPressGestureHUD"),
                verifyProgressBarAutoHide: arguments.contains("-EmbyPlaybackSmokeVerifyProgressBarAutoHide"),
                verifySeekGestureHUD: arguments.contains("-EmbyPlaybackSmokeVerifySeekGestureHUD"),
                verifyResumeRetainedAfterClose: arguments.contains("-EmbyPlaybackSmokeVerifyResumeRetainedAfterClose"),
                requireEmbeddedTextSubtitle: arguments.contains("-EmbyPlaybackSmokeRequireEmbeddedTextSubtitle"),
                forceCloseAfterSeconds: forceCloseAfterSeconds
            )
        }

        guard let serverURLString = arguments.value(after: "-EmbyPlaybackSmokeServerURL"),
              let serverURL = URL(string: serverURLString),
              let username = arguments.value(after: "-EmbyPlaybackSmokeUsername"),
              let password = arguments.value(after: "-EmbyPlaybackSmokePassword")
        else {
            return nil
        }

        return Configuration(
            localFileURL: nil,
            serverURL: serverURL,
            username: username,
            password: password,
            titleFilter: titleFilter,
            itemID: itemID,
            mpvLogLevel: arguments.value(after: "-EmbyPlaybackSmokeMPVLogLevel") ?? defaultLogLevel,
            useSavedSession: false,
            closeAfterPass: arguments.contains("-EmbyPlaybackSmokeCloseAfterPass"),
            useRoute: arguments.contains("-EmbyPlaybackSmokeUseRoute"),
            useDetailRoute: arguments.contains("-EmbyPlaybackSmokeFromDetail"),
            useFirstResumeItem: arguments.contains("-EmbyPlaybackSmokeUseFirstResumeItem"),
            verifyAdjacentNavigation: arguments.contains("-EmbyPlaybackSmokeVerifyAdjacentNavigation"),
            useControlsNavigation: arguments.contains("-EmbyPlaybackSmokeUseControlsNavigation"),
            verifyLongPressGestureHUD: arguments.contains("-EmbyPlaybackSmokeVerifyLongPressGestureHUD"),
            verifyProgressBarAutoHide: arguments.contains("-EmbyPlaybackSmokeVerifyProgressBarAutoHide"),
            verifySeekGestureHUD: arguments.contains("-EmbyPlaybackSmokeVerifySeekGestureHUD"),
            verifyResumeRetainedAfterClose: arguments.contains("-EmbyPlaybackSmokeVerifyResumeRetainedAfterClose"),
            requireEmbeddedTextSubtitle: arguments.contains("-EmbyPlaybackSmokeRequireEmbeddedTextSubtitle"),
            forceCloseAfterSeconds: forceCloseAfterSeconds
        )
    }

    func run() async {
        guard !hasRun else { return }
        hasRun = true

        guard let configuration = Self.configuration else {
            state = .failed("Missing playback smoke launch arguments")
            logger.error("PLAYBACK_SMOKE_FAIL missing launch arguments")
            return
        }

        setenv("LIBMPVPLAYER_SMOKE_LOG", "1", 1)
        setenv("LIBMPVPLAYER_MPV_LOG_LEVEL", configuration.mpvLogLevel, 1)
        setenv("LIBMPVPLAYER_SUBTITLE_DIAGNOSTICS", "1", 1)
        if ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeConvertTraditionalSubtitles") {
            Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles] = true
        }

        do {
            if let localFileURL = configuration.localFileURL {
                try await runLocalFileSmoke(url: localFileURL, configuration: configuration)
                return
            }

            state = .running("Setting up local store")
            try await EmbyStore.setupDataStack()

            if configuration.useSavedSession {
                state = .running("Restoring saved session")
                Container.shared.currentUserSession.reset()
            } else {
                guard let serverURL = configuration.serverURL,
                      let username = configuration.username,
                      let password = configuration.password
                else {
                    throw DebugLoginSmokeError("Missing login arguments")
                }

                state = .running("Connecting to \(serverURL.absoluteString)")
                let server = try await connect(to: serverURL)

                state = .running("Authenticating \(username)")
                _ = try await authenticate(
                    server: server,
                    username: username,
                    password: password
                )
            }

            guard let session = Container.shared.currentUserSession() else {
                throw DebugLoginSmokeError("Saved session could not be restored")
            }

            if configuration.useDetailRoute,
               Self.detailRouteOnlyRequested,
               let item = try await requestedDetailItem(session: session, configuration: configuration)
            {
                self.playbackItem = item
                let detail = "Opening detail \(item.displayTitle)"
                state = .passed(detail)
                logger.info("PLAYBACK_SMOKE_DETAIL_ONLY_OPEN \(detail)")
                return
            }

            state = .running("Finding playable video")
            let item = try await playableVideoItem(
                session: session,
                configuration: configuration
            )

            let preparedPlaybackItem: MediaPlayerItem?
            if configuration.requireEmbeddedTextSubtitle,
               Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles] {
                state = .running("Verifying embedded subtitle extraction")
                let playbackItem = try await MediaPlayerItem.build(
                    for: item,
                    mediaSource: item.mediaSources?.first,
                    videoPlayerType: .emby
                )
                try await verifyEmbeddedSubtitleConversion(
                    for: playbackItem,
                    session: session
                )
                preparedPlaybackItem = playbackItem
            } else {
                preparedPlaybackItem = nil
            }

            let provider = MediaPlayerItemProvider(item: item) { item in
                if let preparedPlaybackItem,
                   preparedPlaybackItem.baseItem.id == item.id {
                    return preparedPlaybackItem
                }
                return try await MediaPlayerItem.build(
                    for: item,
                    mediaSource: item.mediaSources?.first,
                    videoPlayerType: .emby
                )
            }

            let manager = MediaPlayerManager(
                item: provider.item,
                mediaPlayerItemProvider: provider.function
            )
            Container.shared.mediaPlayerManager.register { manager }
            Container.shared.mediaPlayerManagerPublisher().send(manager)
            self.playbackItem = item
            self.manager = manager
            scheduleForceCloseIfNeeded(configuration: configuration)

            let detail = "Opening \(item.displayTitle)"
            state = .running(detail)
            logger.info("PLAYBACK_SMOKE_OPEN \(detail)")
            if configuration.useDetailRoute {
                logger.info("PLAYBACK_SMOKE_DETAIL_ROUTE requested")
            } else if configuration.useRoute {
                logger.info("PLAYBACK_SMOKE_ROUTE requested")
            }

            Task { [weak self, weak manager] in
                await self?.verifyPlaybackProgress(
                    session: session,
                    manager: manager,
                    item: item,
                    closeAfterPass: configuration.closeAfterPass,
                    verifyAdjacentNavigation: configuration.verifyAdjacentNavigation,
                    useControlsNavigation: configuration.useControlsNavigation,
                    verifyLongPressGestureHUD: configuration.verifyLongPressGestureHUD,
                    verifyProgressBarAutoHide: configuration.verifyProgressBarAutoHide,
                    verifySeekGestureHUD: configuration.verifySeekGestureHUD,
                    verifyResumeRetainedAfterClose: configuration.verifyResumeRetainedAfterClose
                )
            }
        } catch {
            let detail = error.localizedDescription
            state = .failed(detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
        }
    }

    private func runLocalFileSmoke(
        url: URL,
        configuration: Configuration
    ) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DebugLoginSmokeError("Local playback file does not exist: \(url.path)")
        }

        state = .running("Opening local file \(url.lastPathComponent)")
        Defaults[.sendProgressReports] = false
        Defaults[.VideoPlayer.supplements] = []

        let title = url.deletingPathExtension().lastPathComponent
        let localPlayback = try makeLocalFilePlayback(url: url)
        let manager = localPlayback.manager
        self.playbackItem = localPlayback.item
        self.manager = manager
        scheduleForceCloseIfNeeded(configuration: configuration)

        NSLog("PLAYBACK_SMOKE_OPEN_LOCAL %@", url.path)
        logger.info("PLAYBACK_SMOKE_OPEN_LOCAL \(url.path)")
        Task { [weak self, weak manager] in
            await self?.verifyLocalPlaybackProgress(
                manager: manager,
                title: title,
                closeAfterPass: configuration.closeAfterPass
            )
        }
    }

    private func scheduleForceCloseIfNeeded(configuration: Configuration) {
        guard !hasScheduledForceClose,
              let seconds = configuration.forceCloseAfterSeconds
        else { return }

        hasScheduledForceClose = true
        let delayMilliseconds = max(100, Int((seconds * 1000).rounded()))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            NSLog("PLAYBACK_SMOKE_FORCE_CLOSE_REQUEST seconds=%.2f", seconds)
            self?.logger.info("PLAYBACK_SMOKE_FORCE_CLOSE_REQUEST seconds=\(String(format: "%.2f", seconds))")
            NotificationCenter.default.post(name: .debugPlaybackSmokeCloseRequested, object: nil)
        }
    }

    private func verifyLocalPlaybackProgress(
        manager: MediaPlayerManager?,
        title: String,
        closeAfterPass: Bool
    ) async {
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(250))

            guard let manager else {
                state = .failed("Local playback manager released")
                NSLog("PLAYBACK_SMOKE_FAIL local manager released")
                logger.error("PLAYBACK_SMOKE_FAIL local manager released")
                return
            }

            if let error = manager.error {
                let detail = "Local player error: \(error.localizedDescription)"
                state = .failed(detail)
                NSLog("PLAYBACK_SMOKE_FAIL %@", detail)
                logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
                return
            }

            let observedSeconds = manager.seconds.seconds
            if observedSeconds >= 0.5 {
                let detail = "Local progress \(String(format: "%.2f", observedSeconds))s for \(title)"
                state = .passed(detail)
                NSLog("PLAYBACK_SMOKE_PASS %@", detail)
                logger.info("PLAYBACK_SMOKE_PASS \(detail)")
                if closeAfterPass {
                    try? await Task.sleep(for: .milliseconds(350))
                    NSLog("PLAYBACK_SMOKE_CLOSE_REQUEST")
                    logger.info("PLAYBACK_SMOKE_CLOSE_REQUEST")
                    NotificationCenter.default.post(name: .debugPlaybackSmokeCloseRequested, object: nil)
                }
                return
            }
        }

        let detail = "No local playback progress after 10s for \(title)"
        state = .failed(detail)
        NSLog("PLAYBACK_SMOKE_FAIL %@", detail)
        logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
    }

    func makeFreshLocalPlaybackManagerForSmoke() -> MediaPlayerManager? {
        guard let url = Self.configuration?.localFileURL else { return nil }

        do {
            return try makeLocalFilePlayback(url: url).manager
        } catch {
            NSLog("PLAYBACK_SMOKE_REOPEN_LOCAL_MANAGER_FAIL %@", error.localizedDescription)
            logger.error("PLAYBACK_SMOKE_REOPEN_LOCAL_MANAGER_FAIL \(error.localizedDescription)")
            return nil
        }
    }

    private func makeLocalFilePlayback(url: URL) throws -> (item: BaseItemDto, manager: MediaPlayerManager) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DebugLoginSmokeError("Local playback file does not exist: \(url.path)")
        }

        let title = url.deletingPathExtension().lastPathComponent
        let runtimeTicks = 600 * 10_000_000

        var videoStream = MediaStream()
        videoStream.type = .video
        videoStream.index = 0
        videoStream.originalIndex = 0
        videoStream.codec = url.pathExtension.lowercased() == "mp4" ? "h264" : nil
        videoStream.displayTitle = "Video"

        var mediaSource = MediaSourceInfo()
        mediaSource.id = "debug-local-source-\(UUID().uuidString)"
        mediaSource.name = "Local File"
        mediaSource.path = url.path
        mediaSource.container = url.pathExtension.lowercased()
        mediaSource.defaultSubtitleStreamIndex = -1
        mediaSource.isSupportsDirectPlay = true
        mediaSource.isSupportsDirectStream = true
        mediaSource.isSupportsTranscoding = false
        mediaSource.runTimeTicks = runtimeTicks
        mediaSource.mediaStreams = [videoStream]

        var item = BaseItemDto()
        item.id = "debug-local-\(UUID().uuidString)"
        item.name = title
        item.type = .video
        item.mediaType = .video
        item.path = url.path
        item.container = mediaSource.container
        item.runTimeTicks = runtimeTicks
        item.mediaSources = [mediaSource]
        item.mediaStreams = mediaSource.mediaStreams
        item.hasSubtitles = false

        let playbackItem = MediaPlayerItem(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: UUID().uuidString,
            url: url
        )
        playbackItem.observers.removeAll()

        let provider = MediaPlayerItemProvider(item: item) { _ in
            playbackItem
        }
        let manager = MediaPlayerManager(
            item: item,
            mediaPlayerItemProvider: provider.function
        )
        Container.shared.mediaPlayerManager.register { manager }
        Container.shared.mediaPlayerManagerPublisher().send(manager)
        return (item, manager)
    }

    private func requestedDetailItem(
        session: UserSession,
        configuration: Configuration
    ) async throws -> BaseItemDto? {
        guard let itemID = configuration.itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
              itemID.isNotEmpty
        else {
            return nil
        }

        let item: BaseItemDto = try await session.embyClient.item(
            itemID: itemID,
            as: BaseItemDto.self
        )
        logger.info("PLAYBACK_SMOKE_DETAIL_ONLY_ITEM item=\(item.id ?? "<nil>") title=\(item.displayTitle) type=\(item.type?.rawValue ?? "<nil>")")
        return item
    }

    private func verifyPlaybackProgress(
        session: UserSession,
        manager: MediaPlayerManager?,
        item: BaseItemDto,
        closeAfterPass: Bool,
        verifyAdjacentNavigation: Bool,
        useControlsNavigation: Bool,
        verifyLongPressGestureHUD: Bool,
        verifyProgressBarAutoHide: Bool,
        verifySeekGestureHUD: Bool,
        verifyResumeRetainedAfterClose: Bool
    ) async {
        let expectedStartSeconds: Double = {
            guard !item.isLiveStream else { return 0 }
            let storedStart = item.startSeconds?.seconds ?? 0
            return max(0, storedStart - Double(Defaults[.VideoPlayer.resumeOffset]))
        }()
        let passSeconds = expectedStartSeconds >= 3 ? expectedStartSeconds + 1 : 3
        var lastObservedSeconds: Double = -1
        var sawTimeBeforeResumePoint = false

        logger.info(
            "PLAYBACK_SMOKE_EXPECTED_PROGRESS item=\(item.id ?? "<nil>") expectedStart=\(String(format: "%.3f", expectedStartSeconds)) passAt=\(String(format: "%.3f", passSeconds))"
        )

        for _ in 0 ..< 24 {
            try? await Task.sleep(for: .seconds(1))

            guard let manager else {
                state = .failed("Playback manager released")
                logger.error("PLAYBACK_SMOKE_FAIL manager released")
                return
            }

            if let error = manager.error {
                let detail = "Player error: \(error.localizedDescription)"
                state = .failed(detail)
                logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
                return
            }

            let observedSeconds = manager.seconds.seconds
            lastObservedSeconds = observedSeconds
            if expectedStartSeconds >= 5, observedSeconds > 0, observedSeconds < expectedStartSeconds - 2 {
                sawTimeBeforeResumePoint = true
            }

            if observedSeconds >= passSeconds {
                if verifyLongPressGestureHUD {
                    guard await verifyLongPressGestureHUDState() else { return }
                }

                if verifyProgressBarAutoHide {
                    guard await verifyProgressBarAutoHideState() else { return }
                }

                if verifySeekGestureHUD {
                    guard await verifySeekGestureHUDState() else { return }
                }

                if verifyAdjacentNavigation {
                    await verifyAdjacentEpisodeNavigation(
                        manager: manager,
                        item: item,
                        closeAfterPass: closeAfterPass,
                        useControlsNavigation: useControlsNavigation
                    )
                    return
                }

                let detail = "Progress \(String(format: "%.1f", observedSeconds))s for \(item.displayTitle)"
                state = .passed(detail)
                logger.info("PLAYBACK_SMOKE_PASS \(detail)")
                if closeAfterPass {
                    try? await Task.sleep(for: .milliseconds(500))
                    logger.info("PLAYBACK_SMOKE_CLOSE_REQUEST")
                    NotificationCenter.default.post(name: .debugPlaybackSmokeCloseRequested, object: nil)
                    if verifyResumeRetainedAfterClose {
                        await verifyResumeRetainedAfterCloseIfNeeded(session: session, item: item)
                    }
                }
                return
            }
        }

        let detail: String
        if expectedStartSeconds >= 3 {
            let belowResumeNote = sawTimeBeforeResumePoint ? " observed playback before resume point;" : ""
            detail = "\(belowResumeNote) no progress beyond resume point after 24s for \(item.displayTitle), last=\(String(format: "%.1f", lastObservedSeconds))s expected>=\(String(format: "%.1f", passSeconds))s"
        } else {
            detail = "No playback progress after 24s for \(item.displayTitle)"
        }
        state = .failed(detail)
        logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
    }

    private func verifyResumeRetainedAfterCloseIfNeeded(
        session: UserSession,
        item: BaseItemDto
    ) async {
        guard let itemID = item.id else {
            state = .failed("Resume retention item has no id")
            logger.error("PLAYBACK_SMOKE_FAIL resume retention item has no id")
            return
        }

        try? await Task.sleep(for: .seconds(4))

        do {
            let response: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.resumeItems(
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )
            let retainedItem = response.items?.first { $0.id == itemID }
            let retainedTicks = retainedItem?.userData?.playbackPositionTicks ?? 0

            guard retainedItem != nil, retainedTicks > 0 else {
                let detail = "Resume item disappeared after close item=\(itemID) ticks=\(retainedTicks)"
                state = .failed(detail)
                NSLog("PLAYBACK_SMOKE_FAIL %@", detail)
                logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
                return
            }

            state = .passed("Resume retained after close item=\(itemID) ticks=\(retainedTicks)")
            NSLog("PLAYBACK_SMOKE_RESUME_RETAINED item=%@ ticks=%d", itemID, retainedTicks)
            logger.info("PLAYBACK_SMOKE_RESUME_RETAINED item=\(itemID) ticks=\(retainedTicks)")
        } catch {
            let detail = "Resume retention check failed: \(error.embyDiagnosticDescription)"
            state = .failed(detail)
            NSLog("PLAYBACK_SMOKE_FAIL %@", detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
        }
    }

    private func verifyLongPressGestureHUDState() async -> Bool {
        logger.info("PLAYBACK_SMOKE_GESTURE_HUD_TRIGGER")

        return await withCheckedContinuation { continuation in
            var completed = false
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .debugPlaybackSmokeLongPressHUDVerified,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }

                let passed = notification.userInfo?["passed"] as? Bool ?? false
                let detail = notification.userInfo?["detail"] as? String ?? "missing detail"
                if passed {
                    self?.logger.info("PLAYBACK_SMOKE_GESTURE_HUD_PASS \(detail)")
                    continuation.resume(returning: true)
                } else {
                    self?.state = .failed("Long press speed HUD did not auto-hide: \(detail)")
                    self?.logger.error("PLAYBACK_SMOKE_FAIL long-press gesture HUD \(detail)")
                    continuation.resume(returning: false)
                }
            }

            NotificationCenter.default.post(name: .debugPlaybackSmokeVerifyLongPressHUDRequested, object: nil)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                state = .failed("Long press speed HUD verification timed out")
                logger.error("PLAYBACK_SMOKE_FAIL long-press gesture HUD timeout")
                continuation.resume(returning: false)
            }
        }
    }

    private func verifyProgressBarAutoHideState() async -> Bool {
        logger.info("PLAYBACK_SMOKE_PROGRESS_BAR_AUTO_HIDE_TRIGGER")

        return await withCheckedContinuation { continuation in
            var completed = false
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .debugPlaybackSmokeProgressBarAutoHideVerified,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }

                let passed = notification.userInfo?["passed"] as? Bool ?? false
                let detail = notification.userInfo?["detail"] as? String ?? "missing detail"
                if passed {
                    self?.logger.info("PLAYBACK_SMOKE_PROGRESS_BAR_AUTO_HIDE_PASS \(detail)")
                    continuation.resume(returning: true)
                } else {
                    self?.state = .failed("Progress bar did not auto-hide: \(detail)")
                    self?.logger.error("PLAYBACK_SMOKE_FAIL progress bar auto-hide \(detail)")
                    continuation.resume(returning: false)
                }
            }

            NotificationCenter.default.post(name: .debugPlaybackSmokeVerifyProgressBarAutoHideRequested, object: nil)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                state = .failed("Progress bar auto-hide verification timed out")
                logger.error("PLAYBACK_SMOKE_FAIL progress bar auto-hide timeout")
                continuation.resume(returning: false)
            }
        }
    }

    private func verifySeekGestureHUDState() async -> Bool {
        logger.info("PLAYBACK_SMOKE_SEEK_GESTURE_HUD_TRIGGER")

        return await withCheckedContinuation { continuation in
            var completed = false
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .debugPlaybackSmokeSeekGestureHUDVerified,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }

                let passed = notification.userInfo?["passed"] as? Bool ?? false
                let detail = notification.userInfo?["detail"] as? String ?? "missing detail"
                if passed {
                    self?.logger.info("PLAYBACK_SMOKE_SEEK_GESTURE_HUD_PASS \(detail)")
                    continuation.resume(returning: true)
                } else {
                    self?.state = .failed("Seek gesture HUD did not match speed HUD style: \(detail)")
                    self?.logger.error("PLAYBACK_SMOKE_FAIL seek gesture HUD \(detail)")
                    continuation.resume(returning: false)
                }
            }

            NotificationCenter.default.post(name: .debugPlaybackSmokeVerifySeekGestureHUDRequested, object: nil)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !completed else { return }
                completed = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                state = .failed("Seek gesture HUD verification timed out")
                logger.error("PLAYBACK_SMOKE_FAIL seek gesture HUD timeout")
                continuation.resume(returning: false)
            }
        }
    }

    private func verifyAdjacentEpisodeNavigation(
        manager: MediaPlayerManager,
        item: BaseItemDto,
        closeAfterPass: Bool,
        useControlsNavigation: Bool
    ) async {
        guard let initialID = item.id else {
            state = .failed("Adjacent navigation item has no id")
            logger.error("PLAYBACK_SMOKE_FAIL adjacent navigation item has no id")
            return
        }

        guard let nextProvider = await waitForNextItem(manager: manager) else {
            let detail = "No next episode provider for \(item.displayTitle)"
            state = .failed(detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
            return
        }

        let nextID = nextProvider.item.id ?? "<nil>"
        logger.info("PLAYBACK_SMOKE_NEXT_TRIGGER from=\(initialID) to=\(nextID) mode=\(useControlsNavigation ? "controls" : "manager")")
        if useControlsNavigation {
            NotificationCenter.default.post(name: .debugPlaybackSmokeNextRequested, object: nil)
        } else {
            await manager.playNewItem(provider: nextProvider)
        }

        guard await waitForCurrentItem(manager: manager, id: nextProvider.item.id) else {
            let detail = "Next episode did not become current item"
            state = .failed(detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
            return
        }

        guard let previousProvider = await waitForPreviousItem(manager: manager) else {
            let detail = "No previous episode provider after next episode"
            state = .failed(detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
            return
        }

        logger.info("PLAYBACK_SMOKE_PREVIOUS_TRIGGER from=\(nextID) to=\(previousProvider.item.id ?? "<nil>") mode=\(useControlsNavigation ? "controls" : "manager")")
        if useControlsNavigation {
            NotificationCenter.default.post(name: .debugPlaybackSmokePreviousRequested, object: nil)
        } else {
            await manager.playNewItem(provider: previousProvider)
        }

        guard await waitForCurrentItem(manager: manager, id: initialID) else {
            let detail = "Previous episode did not return to initial item"
            state = .failed(detail)
            logger.error("PLAYBACK_SMOKE_FAIL \(detail)")
            return
        }

        let detail = "Adjacent navigation passed for \(item.displayTitle)"
        state = .passed(detail)
        logger.info("PLAYBACK_SMOKE_PASS \(detail)")
        if closeAfterPass {
            try? await Task.sleep(for: .milliseconds(500))
            logger.info("PLAYBACK_SMOKE_CLOSE_REQUEST")
            NotificationCenter.default.post(name: .debugPlaybackSmokeCloseRequested, object: nil)
        }
    }

    private func waitForNextItem(manager: MediaPlayerManager) async -> MediaPlayerItemProvider? {
        for _ in 0 ..< 20 {
            if let nextItem = manager.queue?.nextItem {
                return nextItem
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        return nil
    }

    private func waitForPreviousItem(manager: MediaPlayerManager) async -> MediaPlayerItemProvider? {
        for _ in 0 ..< 20 {
            if let previousItem = manager.queue?.previousItem {
                return previousItem
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        return nil
    }

    private func waitForCurrentItem(manager: MediaPlayerManager, id: String?) async -> Bool {
        guard let id else { return false }

        for _ in 0 ..< 20 {
            if let error = manager.error {
                logger.error("PLAYBACK_SMOKE_FAIL adjacent navigation player error \(error.localizedDescription)")
                return false
            }

            if manager.item.id == id, manager.playbackItem?.baseItem.id == id {
                return true
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return false
    }

    private func connect(to url: URL) async throws -> ServerState {
        let client = EmbyPortAuthenticationClient(
            baseURL: url,
            identity: .embyDefault()
        )

        let response = try await client.publicSystemInfo()
        let connectionURL = processConnectionURL(
            initial: url,
            response: response.responseURL
        )

        let server = ServerState(
            urls: [connectionURL],
            currentURL: connectionURL,
            name: response.info.name,
            id: response.info.id,
            userIDs: []
        )

        let publicInfo = try await server.getPublicSystemInfo()

        var servers = StoredValues[.Server.servers]
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        StoredValues[.Server.servers] = servers
        StoredValues[.Server.publicInfo(id: server.id)] = publicInfo

        return server
    }

    private func authenticate(
        server: ServerState,
        username: String,
        password: String
    ) async throws -> UserState {
        let response = try await server.embyAuthenticationClient.authenticate(
            username: username,
            password: password
        )

        let user = UserState(
            id: response.user.id,
            serverID: server.id,
            username: response.user.name
        )

        guard user.storeAccessToken(response.accessToken) else {
            throw DebugLoginSmokeError("Failed to save access token")
        }

        var userData = UserDto()
        userData.id = response.user.id
        userData.name = response.user.name
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

        Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
        Container.shared.currentUserSession.reset()

        return user
    }

    private func playableVideoItem(
        session: UserSession,
        configuration: Configuration
    ) async throws -> BaseItemDto {
        if let itemID = configuration.itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
           itemID.isNotEmpty
        {
            let item: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            guard item.isDirectlyPlayableVideo else {
                throw DebugLoginSmokeError("Item \(itemID) is not directly playable")
            }
            if configuration.requireEmbeddedTextSubtitle,
               !hasEmbeddedTextSubtitle(item)
            {
                throw DebugLoginSmokeError("Item \(itemID) has no embedded text subtitle")
            }
            logPlaybackCandidate(item, reason: "item-id")
            return item
        }

        if let titleFilter = configuration.titleFilter?.trimmingCharacters(in: .whitespacesAndNewlines),
           titleFilter.isNotEmpty
        {
            return try await playableVideoItemMatchingTitle(
                titleFilter,
                session: session,
                configuration: configuration
            )
        }

        if configuration.useFirstResumeItem {
            return try await firstResumeVideoItem(
                session: session,
                configuration: configuration
            )
        }

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode, .movie, .video]
        parameters.isRecursive = true
        parameters.limit = configuration.requireEmbeddedTextSubtitle ? 200 : 20
        parameters.sortBy = [ItemSortBy.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.startIndex = 0

        let items: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        for item in items.items ?? [] {
            guard let itemID = item.id else { continue }
            var fullItem: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            if (fullItem.userData?.playbackPositionTicks ?? 0) == 0 {
                fullItem.userData = item.userData
            }
            guard fullItem.isDirectlyPlayableVideo else { continue }
            if configuration.requireEmbeddedTextSubtitle,
               !hasEmbeddedTextSubtitle(fullItem)
            {
                continue
            }
            logPlaybackCandidate(fullItem, reason: configuration.requireEmbeddedTextSubtitle ? "recent-embedded-text-subtitle" : "recent")
            return fullItem
        }

        throw DebugLoginSmokeError("No playable video item found for playback smoke")
    }

    private func firstResumeVideoItem(
        session: UserSession,
        configuration: Configuration
    ) async throws -> BaseItemDto {
        let response: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.resumeItems(
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        for item in response.items ?? [] {
            guard let itemID = item.id,
                  (item.userData?.playbackPositionTicks ?? 0) > 0
            else {
                continue
            }

            var fullItem: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            if (fullItem.userData?.playbackPositionTicks ?? 0) == 0 {
                fullItem.userData = item.userData
            }
            guard fullItem.isDirectlyPlayableVideo else { continue }
            if configuration.requireEmbeddedTextSubtitle,
               !hasEmbeddedTextSubtitle(fullItem)
            {
                continue
            }

            logPlaybackCandidate(fullItem, reason: "resume")
            return fullItem
        }

        throw DebugLoginSmokeError("No playable resume video item found")
    }

    private func playableVideoItemMatchingTitle(
        _ titleFilter: String,
        session: UserSession,
        configuration: Configuration
    ) async throws -> BaseItemDto {
        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.includeItemTypes = [.episode, .movie, .video]
        parameters.isRecursive = true
        parameters.limit = 100
        parameters.searchTerm = titleFilter
        parameters.sortBy = [ItemSortBy.sortName]
        parameters.sortOrder = [.ascending]
        parameters.startIndex = 0

        let items: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let candidates = items.items ?? []
        logger.info("PLAYBACK_SMOKE_SEARCH title=\(titleFilter) count=\(candidates.count)")

        var fallback: BaseItemDto?
        for candidate in candidates {
            guard let itemID = candidate.id else { continue }

            let fullItem: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            guard fullItem.isDirectlyPlayableVideo else { continue }
            if configuration.requireEmbeddedTextSubtitle,
               !hasEmbeddedTextSubtitle(fullItem)
            {
                continue
            }

            if fallback == nil {
                fallback = fullItem
            }

            if fullItem.matchesSmokeTitleFilter(titleFilter) {
                logPlaybackCandidate(fullItem, reason: "title-filter")
                return fullItem
            }
        }

        if let fallback {
            logPlaybackCandidate(fallback, reason: "title-filter-fallback")
            return fallback
        }

        throw DebugLoginSmokeError("No playable video item found matching \(titleFilter)")
    }

    private func logPlaybackCandidate(_ item: BaseItemDto, reason: String) {
        let source = item.mediaSources?.first
        let stream = source?.mediaStreams?.first { $0.type == .video } ?? item.mediaStreams?.first { $0.type == .video }
        let sourceSubtitleCount = source?.mediaStreams?.filter { $0.type == .subtitle }.count
        let itemSubtitleCount = item.mediaStreams?.filter { $0.type == .subtitle }.count
        let subtitles = sourceSubtitleCount ?? itemSubtitleCount ?? 0
        let embeddedTextSubtitles = embeddedTextSubtitleStreams(in: item).count

        logger.info(
            """
            PLAYBACK_SMOKE_ITEM reason=\(reason) id=\(item.id ?? "<nil>") title=\(item.smokeTitle) type=\(item.type?.rawValue ?? "<nil>") mediaType=\(item.mediaType?.rawValue ?? "<nil>") container=\(item.container ?? source?.container ?? "<nil>") sourceID=\(source?.id ?? "<nil>") sourcePath=\(source?.path ?? item.path ?? "<nil>") videoCodec=\(stream?.codec ?? "<nil>") videoProfile=\(stream?.profile ?? "<nil>") videoPixelFormat=\(stream?.pixelFormat ?? "<nil>") videoRange=\(stream?.videoRange?.rawValue ?? "<nil>") size=\(stream?.width ?? 0)x\(stream?.height ?? 0) subtitles=\(subtitles) embeddedTextSubtitles=\(embeddedTextSubtitles) transcodingURL=\(source?.transcodingURL ?? "<nil>")
            """
        )
    }

    private func hasEmbeddedTextSubtitle(_ item: BaseItemDto) -> Bool {
        !embeddedTextSubtitleStreams(in: item).isEmpty
    }

    private func embeddedTextSubtitleStreams(in item: BaseItemDto) -> [MediaStream] {
        let streams = (item.mediaSources?.flatMap { $0.mediaStreams ?? [] } ?? []) + (item.mediaStreams ?? [])
        return streams.filter { stream in
            guard stream.type == .subtitle,
                  !isExternalSubtitle(stream)
            else { return false }
            return isTextSubtitle(stream)
        }
    }

    private func isExternalSubtitle(_ stream: MediaStream) -> Bool {
        stream.deliveryMethod == .external ||
            stream.isExternal == true ||
            stream.deliveryURL?.isEmpty == false
    }

    private func isTextSubtitle(_ stream: MediaStream) -> Bool {
        if stream.isTextSubtitleStream == true {
            return true
        }
        if stream.isTextSubtitleStream == false {
            return false
        }

        let codec = stream.codec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() ?? ""
        guard !codec.isEmpty else { return false }
        return Self.textSubtitleCodecs.contains(codec)
    }

    private func verifyEmbeddedSubtitleConversion(
        for item: MediaPlayerItem,
        session: UserSession
    ) async throws {
        guard let itemID = item.baseItem.id,
              let mediaSourceID = item.mediaSource.id
        else {
            throw DebugLoginSmokeError("Embedded subtitle conversion probe missing item or media source id")
        }

        let streams = item.subtitleStreams.filter { stream in
            !isExternalSubtitle(stream) && isTextSubtitle(stream)
        }
        NSLog(
            "PLAYBACK_SMOKE_EMBEDDED_SUBTITLE_PROBE item=%@ mediaSource=%@ streams=%d",
            itemID,
            mediaSourceID,
            streams.count
        )

        for stream in streams {
            guard let originalIndex = stream.originalIndex ?? stream.index else {
                NSLog("PLAYBACK_SMOKE_EMBEDDED_SUBTITLE_PROBE_SKIP reason=missing-index title=%@", stream.displayTitle ?? stream.title ?? "<nil>")
                continue
            }

            let urls = embeddedSubtitleStreamURLs(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                streamIndex: originalIndex,
                stream: stream,
                client: session.embyClient
            )
            guard !urls.isEmpty else {
                NSLog("PLAYBACK_SMOKE_EMBEDDED_SUBTITLE_PROBE_SKIP reason=no-urls index=%d", originalIndex)
                continue
            }

            let convertedURL = await Task.detached(priority: .userInitiated) {
                MPVSubtitleFileConverter.convertedSubtitleURL(
                    for: urls,
                    headers: session.embyClient.playbackHeaders,
                    codec: stream.codec,
                    isTextSubtitle: stream.isTextSubtitleStream
                )
            }.value

            if let convertedURL {
                NSLog(
                    "PLAYBACK_SMOKE_EMBEDDED_SUBTITLE_CONVERT_PASS index=%d codec=%@ output=%@",
                    originalIndex,
                    stream.codec ?? "<nil>",
                    convertedURL.lastPathComponent
                )
                try? FileManager.default.removeItem(at: convertedURL)
                return
            }

            NSLog(
                "PLAYBACK_SMOKE_EMBEDDED_SUBTITLE_CONVERT_FAIL index=%d codec=%@ candidates=%d",
                originalIndex,
                stream.codec ?? "<nil>",
                urls.count
            )
        }

        throw DebugLoginSmokeError("Embedded subtitle conversion probe failed")
    }

    private func embeddedSubtitleStreamURLs(
        itemID: String,
        mediaSourceID: String,
        streamIndex: Int,
        stream: MediaStream,
        client: EmbyPortSessionClient
    ) -> [URL] {
        var seen = Set<String>()
        return embeddedSubtitleExtractionFormats(for: stream).flatMap { format in
            client.subtitleStreamURLs(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                streamIndex: streamIndex,
                format: format
            )
        }.compactMap { url in
            seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    private func embeddedSubtitleExtractionFormats(for stream: MediaStream) -> [String] {
        let codec = stream.codec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() ?? ""
        switch codec {
        case "ass":
            return ["ass", "srt", "vtt"]
        case "ssa":
            return ["ssa", "srt", "vtt"]
        case "webvtt", "vtt":
            return ["vtt", "srt"]
        default:
            return ["srt", "vtt"]
        }
    }

    private static let textSubtitleCodecs: Set<String> = [
        "ass",
        "eia_608",
        "eia_708",
        "hdmv_text_subtitle",
        "jacosub",
        "microdvd",
        "mov_text",
        "mpl2",
        "pjs",
        "realtext",
        "sami",
        "ssa",
        "srt",
        "stl",
        "subrip",
        "subviewer",
        "subviewer1",
        "text",
        "vplayer",
        "webvtt",
    ]

    private func processConnectionURL(initial url: URL, response: URL?) -> URL {
        guard let response else { return url }

        if url.scheme != response.scheme ||
            url.host != response.host
        {
            let newURL = response.absoluteString.trimmingSuffix(
                "/System/Info/Public"
            )
            return URL(string: newURL) ?? url
        }

        return url
    }
}

private struct DebugPlaybackSmokeStatusOverlay: View {

    @ObservedObject
    var runner: DebugPlaybackSmokeRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(runner.state.title)
                .font(.caption.weight(.bold))

            Text(runner.state.detail)
                .lineLimit(4)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 54)
        .padding(.leading, 12)
    }
}

private struct DebugPlaybackSmokeOverlay: View {

    @ObservedObject
    var runner: DebugPlaybackSmokeRunner

    @ObservedObject
    var manager: MediaPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(runner.state.title)
                .font(.caption.weight(.bold))

            Text(runner.state.detail)
                .lineLimit(3)

            Text("state=\(String(describing: manager.state)) seconds=\(String(format: "%.1f", manager.seconds.seconds))")

            if let error = manager.error {
                Text("error=\(error.localizedDescription)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 54)
        .padding(.leading, 12)
    }
}

@MainActor
final class DebugLoginSmokeRunner: ObservableObject {

    struct Configuration {
        let serverURL: URL
        let username: String
        let password: String
    }

    enum State {
        case running(String)
        case passed(String)
        case failed(String)

        var title: String {
            switch self {
            case .running:
                "LOGIN_SMOKE_RUNNING"
            case .passed:
                "LOGIN_SMOKE_PASS"
            case .failed:
                "LOGIN_SMOKE_FAIL"
            }
        }

        var detail: String {
            switch self {
            case let .running(detail), let .passed(detail), let .failed(detail):
                detail
            }
        }
    }

    @Published
    var state: State = .running("Preparing login smoke test")

    private let logger = Logger.emby()
    private var hasRun = false

    static var configuration: Configuration? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let serverURLString = arguments.value(after: "-EmbyLoginSmokeServerURL"),
              let serverURL = URL(string: serverURLString),
              let username = arguments.value(after: "-EmbyLoginSmokeUsername"),
              let password = arguments.value(after: "-EmbyLoginSmokePassword")
        else {
            return nil
        }

        return Configuration(
            serverURL: serverURL,
            username: username,
            password: password
        )
    }

    func run() async {
        guard !hasRun else { return }
        hasRun = true

        guard let configuration = Self.configuration else {
            state = .failed("Missing login smoke launch arguments")
            logger.error("LOGIN_SMOKE_FAIL missing launch arguments")
            return
        }

        do {
            state = .running("Setting up local store")
            try await EmbyStore.setupDataStack()

            state = .running("Connecting to \(configuration.serverURL.absoluteString)")
            let server = try await connect(to: configuration.serverURL)

            state = .running("Authenticating \(configuration.username)")
            let user = try await authenticate(
                server: server,
                username: configuration.username,
                password: configuration.password
            )

            state = .running("Validating saved session")
            try await validateSession(user: user)

            let detail = "Signed in as \(user.username) on \(server.name)"
            state = .passed(detail)
            logger.info("LOGIN_SMOKE_PASS \(detail)")
        } catch {
            let detail = error.localizedDescription
            state = .failed(detail)
            logger.error("LOGIN_SMOKE_FAIL \(detail)")
        }
    }

    private func connect(to url: URL) async throws -> ServerState {
        let client = EmbyPortAuthenticationClient(
            baseURL: url,
            identity: .embyDefault()
        )

        let response = try await client.publicSystemInfo()
        let connectionURL = processConnectionURL(
            initial: url,
            response: response.responseURL
        )

        let server = ServerState(
            urls: [connectionURL],
            currentURL: connectionURL,
            name: response.info.name,
            id: response.info.id,
            userIDs: []
        )

        let publicInfo = try await server.getPublicSystemInfo()

        var servers = StoredValues[.Server.servers]
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        StoredValues[.Server.servers] = servers
        StoredValues[.Server.publicInfo(id: server.id)] = publicInfo

        return server
    }

    private func authenticate(
        server: ServerState,
        username: String,
        password: String
    ) async throws -> UserState {
        let response = try await server.embyAuthenticationClient.authenticate(
            username: username,
            password: password
        )

        let user = UserState(
            id: response.user.id,
            serverID: server.id,
            username: response.user.name
        )

        guard user.storeAccessToken(response.accessToken) else {
            throw DebugLoginSmokeError("Failed to save access token")
        }

        var userData = UserDto()
        userData.id = response.user.id
        userData.name = response.user.name
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

        Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
        Container.shared.currentUserSession.reset()

        return user
    }

    private func validateSession(user: UserState) async throws {
        guard let session = Container.shared.currentUserSession() else {
            throw DebugLoginSmokeError("Saved session could not be restored")
        }

        let currentUser = try await session.embyClient.currentUser(as: UserDto.self)
        guard currentUser.id == user.id else {
            throw DebugLoginSmokeError("Restored session user mismatch")
        }

        do {
            let _: EmbyPortCurrentUserResponse = try await session.embyClient.currentUser(
                as: EmbyPortCurrentUserResponse.self
            )

            let _: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.resumeItems(
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            let _: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.userViews(
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            var nextUpParameters = EmbyPortNextUpParameters()
            nextUpParameters.enableUserData = true
            nextUpParameters.fields = .MinimumFields
            nextUpParameters.limit = 50
            nextUpParameters.startIndex = 0
            let nextUpItems: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.nextUp(
                nextUpParameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            var recentlyAddedParameters = EmbyPortItemsParameters()
            recentlyAddedParameters.enableUserData = true
            recentlyAddedParameters.fields = .MinimumFields
            recentlyAddedParameters.includeItemTypes = [.movie, .series]
            recentlyAddedParameters.isRecursive = true
            recentlyAddedParameters.limit = 50
            recentlyAddedParameters.sortBy = [ItemSortBy.dateCreated]
            recentlyAddedParameters.sortOrder = [.descending]
            recentlyAddedParameters.startIndex = 0
            let recentlyAddedItems: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.items(
                recentlyAddedParameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            var playableVideoParameters = EmbyPortItemsParameters()
            playableVideoParameters.enableUserData = true
            playableVideoParameters.fields = .MinimumFields
            playableVideoParameters.includeItemTypes = [.episode, .movie, .video]
            playableVideoParameters.isRecursive = true
            playableVideoParameters.limit = 20
            playableVideoParameters.sortBy = [ItemSortBy.dateCreated]
            playableVideoParameters.sortOrder = [.descending]
            playableVideoParameters.startIndex = 0
            let playableVideoItems: EmbyPortItemsResponse<BaseItemDto> = try await session.embyClient.items(
                playableVideoParameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )

            try await validateItemDetails(
                session: session,
                items: (recentlyAddedItems.items ?? []) + (nextUpItems.items ?? []),
                playbackItems: playableVideoItems.items ?? []
            )
        } catch {
            throw DebugLoginSmokeError("Home API decode failed: \(error.debugDescriptionForSmoke)")
        }
    }

    private func validateItemDetails(session: UserSession, items: [BaseItemDto], playbackItems: [BaseItemDto]) async throws {
        for item in items.prefix(8) {
            guard let itemID = item.id else { continue }

            let fullItem: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )

            let _: [BaseItemDto] = try await session.embyClient.localTrailers(
                itemID: itemID,
                as: [BaseItemDto].self
            )
        }

        var playbackCandidate: BaseItemDto?
        for item in playbackItems.prefix(8) {
            guard let itemID = item.id else { continue }
            let fullItem: BaseItemDto = try await session.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            guard fullItem.isDirectlyPlayableVideo else { continue }
            playbackCandidate = fullItem
            break
        }

        guard let playbackCandidate else {
            throw DebugLoginSmokeError("No playable video item found for playback smoke")
        }

        try await validatePlaybackBuild(item: playbackCandidate)
    }

    private func validatePlaybackBuild(item: BaseItemDto) async throws {
        let playbackItem = try await MediaPlayerItem.build(
            for: item,
            mediaSource: item.mediaSources?.first,
            videoPlayerType: .emby
        )

        guard playbackItem.url.scheme != nil else {
            throw DebugLoginSmokeError("Playback URL missing scheme: \(playbackItem.url.absoluteString)")
        }

        var request = URLRequest(url: playbackItem.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (key, value) in playbackItem.httpHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 400 ~= httpResponse.statusCode
        else {
            throw DebugLoginSmokeError("Playback URL probe failed for \(playbackItem.url.absoluteString)")
        }
    }

    private func processConnectionURL(initial url: URL, response: URL?) -> URL {
        guard let response else { return url }

        if url.scheme != response.scheme ||
            url.host != response.host
        {
            let newURL = response.absoluteString.trimmingSuffix(
                "/System/Info/Public"
            )
            return URL(string: newURL) ?? url
        }

        return url
    }
}

private struct DebugLoginSmokeError: LocalizedError {

    let errorDescription: String?

    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
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

private extension Error {

    var debugDescriptionForSmoke: String {
        if let decodingError = self as? DecodingError {
            switch decodingError {
            case let .typeMismatch(type, context):
                return "typeMismatch \(type) at \(context.smokePath): \(context.debugDescription)"
            case let .valueNotFound(type, context):
                return "valueNotFound \(type) at \(context.smokePath): \(context.debugDescription)"
            case let .keyNotFound(key, context):
                return "keyNotFound \(key.stringValue) at \(context.smokePath): \(context.debugDescription)"
            case let .dataCorrupted(context):
                return "dataCorrupted at \(context.smokePath): \(context.debugDescription)"
            @unknown default:
                return String(reflecting: self)
            }
        }

        return String(reflecting: self)
    }
}

private extension DecodingError.Context {

    var smokePath: String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }
}

private extension BaseItemDto {

    var isDirectlyPlayableVideo: Bool {
        guard isPlayable else { return false }

        if mediaType == .video {
            return true
        }

        switch type {
        case .episode, .movie, .musicVideo, .trailer, .video:
            return true
        default:
            return false
        }
    }

    var smokeTitle: String {
        [
            seriesName,
            seasonName,
            displayTitle,
            originalTitle,
        ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " / ")
    }

    func matchesSmokeTitleFilter(_ filter: String) -> Bool {
        let normalizedFilter = filter.normalizedSmokeSearchText
        guard normalizedFilter.isNotEmpty else { return false }

        return [
            name,
            displayTitle,
            originalTitle,
            seriesName,
            seasonName,
            parentTitle,
            path,
        ]
            .compactMap { $0?.normalizedSmokeSearchText }
            .contains { $0.contains(normalizedFilter) }
    }
}

private extension String {

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSmokeSearchText: String {
        folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }
}

#endif
