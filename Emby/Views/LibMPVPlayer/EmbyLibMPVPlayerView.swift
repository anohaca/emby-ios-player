import AVFoundation
import Combine
import Defaults
import Factory
import MediaPlayer
import PreferencesView
import SwiftUI
import Transmission
import UIKit
import UniformTypeIdentifiers

struct EmbyLibMPVPlayerView: View {
    @Environment(\.presentationCoordinator)
    private var presentationCoordinator
    @Environment(\.scenePhase)
    private var scenePhase

    let manager: MediaPlayerManager
    var onDismiss: (() -> Void)?
    var usesManualWindowPresentation = false

    @State
    private var isBeingDismissedByTransition = false
    @State
    private var didStart = false

    var body: some View {
        EmbyLibMPVPlayerRepresentable(
            manager: manager,
            usesManualWindowPresentation: usesManualWindowPresentation,
            onClose: {
                dismissPlayer()
            },
            onDidDisappear: {
                // Route state is cleared by Transmission's presentation coordinator.
                // Clearing it here races with rotation dismissal and can leave an empty host visible.
            }
        )
        .ignoresSafeArea()
        .onAppear {
            guard !didStart else { return }
            didStart = true
            manager.start()
        }
        .backport
        .onChange(of: presentationCoordinator.isPresented) { _, isPresented in
            guard !isPresented else { return }
            guard scenePhase == .active else { return }
            guard UIApplication.shared.applicationState == .active else { return }
            isBeingDismissedByTransition = true
        }
    }

    private func dismissPlayer() {
        guard !isBeingDismissedByTransition else { return }
        isBeingDismissedByTransition = true

        if !usesManualWindowPresentation {
            EmbyLibMPVPlayerViewController.beginPortraitOrientationForDismissal()
        }
        if let onDismiss {
            #if DEBUG
            NSLog("EmbyPlayerDismiss route=player-window")
            #endif
            onDismiss()
            return
        }

        #if DEBUG
        NSLog("EmbyPlayerDismiss route=presentation-coordinator isPresented=%@", presentationCoordinator.isPresented.description)
        #endif
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        presentationCoordinator.dismiss(transaction: transaction)
    }
}

private struct EmbyLibMPVPlayerRepresentable: UIViewControllerRepresentable {
    let manager: MediaPlayerManager
    let usesManualWindowPresentation: Bool
    let onClose: () -> Void
    let onDidDisappear: () -> Void

    func makeUIViewController(context: Context) -> EmbyLibMPVPlayerViewController {
        let controller = EmbyLibMPVPlayerViewController(
            manager: manager,
            usesManualWindowPresentation: usesManualWindowPresentation
        )
        controller.onClose = onClose
        controller.onDidDisappear = onDidDisappear
        return controller
    }

    func updateUIViewController(_ uiViewController: EmbyLibMPVPlayerViewController, context: Context) {
        uiViewController.usesManualWindowPresentation = usesManualWindowPresentation
        uiViewController.onClose = onClose
        uiViewController.onDidDisappear = onDidDisappear
    }

    static func dismantleUIViewController(_ uiViewController: EmbyLibMPVPlayerViewController, coordinator: ()) {
        uiViewController.stopForSwiftUIDismantleIfNeeded()
    }
}

@MainActor
final class EmbyLibMPVPlayerViewController: UIViewController,
    VideoMediaPlayerProxy,
    MediaPlayerOffsetConfigurable,
    MediaPlayerSubtitleConfigurable,
    UIDocumentPickerDelegate,
    UITableViewDataSource,
    UITableViewDelegate
{
    private final class PlayerRootView: UIView {
        var onMoveToWindow: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(window)
        }
    }

    let objectWillChange = ObservableObjectPublisher()
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)

    var onClose: (() -> Void)?
    var onDidDisappear: (() -> Void)?
    var usesManualWindowPresentation: Bool

    weak var manager: MediaPlayerManager? {
        didSet {
            for var observer in observers {
                observer.manager = manager
            }
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    var videoPlayerBody: some View {
        EmptyView()
    }

    private let playerView = MPVPlayerView()
    private let controlsView = PlayerControlsView()
    private let renderedSubtitleLabel = UILabel()
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private let episodeListPanel = UIVisualEffectView(effect: EmbyLibMPVPlayerViewController.panelEffect())
    private let episodeListTitleLabel = UILabel()
    private let episodeListTableView = UITableView(frame: .zero, style: .plain)
    private let episodeListLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let player = MPVPlayerController()
    private let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))

    private var cancellables: Set<AnyCancellable> = []
    private var queueCancellable: AnyCancellable?
    private var gestureController: PlayerGestureController?
    private weak var volumeSlider: UISlider?
    private var episodeListItems: [BaseItemDto] = []
    private var episodeListLoadTask: Task<Void, Never>?
    private var episodeListSeriesID: String?
    private var isEpisodeListVisible = false
    private var lastObservedOutputVolume = Double(AVAudioSession.sharedInstance().outputVolume)
    private var volumePollingTimer: Timer?
    private var controlsHidden = true
    private var hideControlsWorkItem: DispatchWorkItem?
    private var hideSeekPreviewWorkItem: DispatchWorkItem?
    private var endSeekTimelinePreviewWorkItem: DispatchWorkItem?
    private var hideGestureHUDWorkItem: DispatchWorkItem?
    private var hideGestureHUDDeadline: Date?
    private var hideGestureHUDGeneration = 0
    private var longPressSpeedRestoreValue: Double?
    private var verticalAdjustmentInitialValue: Double?
    private var didRequestClose = false
    private var didScheduleDeferredStop = false
    private var didStopPlayback = false
    private var didShutdownForDismissal = false
    private var isWaitingForFirstVideoFrame = true
    private var bufferingIndicatorVisible = false
    private var bufferingIndicatorVisibilityGeneration = 0
    private var isInBackground = false
    private var shouldResumeAfterForeground = false
    private var foregroundResumeBeganAt: Date?
    private var didLogForegroundTimeAdvance = false
    private var foregroundRenderRefreshGeneration = 0
    private var foregroundGeometryLogUntil: Date?
    private var lastVideoRect: MPVVideoRect?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var pendingResumeObservation: (itemID: String, expectedSeconds: Double)?
    private var currentSubtitleIdentifiers: Set<String> = []
    private var pendingDefaultExternalSubtitleTitle: String?
    private var pendingDefaultExternalSubtitleClearGeneration = 0
    private var convertedEmbeddedSubtitleTitlesByOriginalIndex: [Int: String] = [:]
    private var subtitlePosition = 100.0
    private var subtitleScale = 1.0
    private var subtitleBorderSize = 3.0
    private var subtitleDelay = 0.0
    private var subtitleAdjustmentSettingsDidChange = false
    private var lastSubtitleAdjustmentLogAt: Date?
    private var shouldResumeAfterSubtitlePicker = false
    private var isReadyToStartPlayback = false
    private var pendingPlaybackItemForPresentation: MediaPlayerItem?
    private var persistSubtitleAdjustmentWorkItem: DispatchWorkItem?
    private var reapplySubtitleAdjustmentWorkItem: DispatchWorkItem?
    private var pendingLandscapeRequestWorkItem: DispatchWorkItem?
    private var subtitleVisibleBottomConstraint: NSLayoutConstraint?
    private var subtitleControlsBottomConstraint: NSLayoutConstraint?
    private static var orientationOverrideGeneration = 0
    private static let episodeListCellIdentifier = "EmbyPlayerEpisodeListCell"
    #if DEBUG
    private var didStartSubtitleBorderExerciseForSmoke = false
    private var didStartSubtitleScaleExerciseForSmoke = false
    private var exitTraceStartTime: CFTimeInterval?
    private var exitTraceLastTickTime: CFTimeInterval?
    private var exitTraceGeneration = 0
    #endif

    private var logsAllMPVDiagnosticsForSmoke: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeServerURL")
        #else
        false
        #endif
    }

    private var exercisesSubtitleBorderForSmoke: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeExerciseSubtitleBorder")
        #else
        false
        #endif
    }

    private var exercisesSubtitleScaleForSmoke: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeExerciseSubtitleScale")
        #else
        false
        #endif
    }

    private var keepsControlsVisibleForSmoke: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeKeepControlsVisible")
        #else
        false
        #endif
    }

    private var opensSubtitleAdjustmentBeforeSmokeClose: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbyPlaybackSmokeOpenSubtitleAdjustmentBeforeClose")
        #else
        false
        #endif
    }

    private var usesSubtitleTextFallback: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-EmbySubtitleTextFallback")
        #else
        false
        #endif
    }

    override var prefersStatusBarHidden: Bool {
        controlsHidden
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if usesManualWindowPresentation {
            return .portrait
        }
        if didRequestClose {
            return .allButUpsideDown
        }
        return UIPreferencesHostingController.globalSupportedOrientationsOverride ?? .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if usesManualWindowPresentation {
            return .portrait
        }
        if didRequestClose {
            return .portrait
        }
        return UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride ??
            super.preferredInterfaceOrientationForPresentation
    }

    init(manager: MediaPlayerManager, usesManualWindowPresentation: Bool = false) {
        Defaults.Keys.migrateSubtitleAdjustmentSettingsToAppSuiteIfNeeded()
        self.usesManualWindowPresentation = usesManualWindowPresentation
        super.init(nibName: nil, bundle: nil)
        self.manager = manager
        loadSubtitleAdjustmentSettings(for: manager.item)
        manager.proxy = self
        bind(manager: manager)
        for var observer in observers {
            observer.manager = manager
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PlayerRootView()
        rootView.backgroundColor = .embyAppBackgroundSurface
        rootView.onMoveToWindow = { [weak self] window in
            guard window != nil, self?.didRequestClose == false else { return }
            if self?.usesManualWindowPresentation != true {
                self?.requestLandscapeOrientation()
            }
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .embyAppBackgroundSurface
        installViews()
        bindBufferingIndicator()
        isBuffering.value = true
        prepareVideoSurfaceForLoading()
        installVolumeView()
        bindPlayer()
        bindControls()
        bindHardwareVolumeHUD()
        controlsView.applyEmbyPlaybackChrome()
        controlsView.setControlsHidden(true, animated: false)
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        controlsView.updateJumpIntervals(
            backward: Defaults[.VideoPlayer.jumpBackwardInterval],
            forward: Defaults[.VideoPlayer.jumpForwardInterval]
        )
        installGestures()
        updateEpisodeNavigation()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackgroundNotification),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForegroundNotification),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActiveNotification),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokeCloseRequested),
            name: .debugPlaybackSmokeCloseRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokeNextRequested),
            name: .debugPlaybackSmokeNextRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokePreviousRequested),
            name: .debugPlaybackSmokePreviousRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokeVerifyLongPressHUDRequested),
            name: .debugPlaybackSmokeVerifyLongPressHUDRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokeVerifyProgressBarAutoHideRequested),
            name: .debugPlaybackSmokeVerifyProgressBarAutoHideRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugPlaybackSmokeVerifySeekGestureHUDRequested),
            name: .debugPlaybackSmokeVerifySeekGestureHUDRequested,
            object: nil
        )
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !didRequestClose, !usesManualWindowPresentation {
            Self.prepareLandscapeOrientationForPresentation(requestSceneImmediately: false)
            refreshSupportedOrientations()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRequestClose else { return }
        if !usesManualWindowPresentation,
           !didRequestClose,
           view.window?.windowScene?.interfaceOrientation.isLandscape != true
        {
            requestLandscapeOrientation()
        }
        attachPlayerIfNeeded()
        scheduleVideoRectRefreshBurst()
        isReadyToStartPlayback = true
        playPendingPlaybackItemForPresentationIfNeeded()
        #if DEBUG
        startSubtitleBorderExerciseForSmokeIfNeeded()
        startSubtitleScaleExerciseForSmokeIfNeeded()
        #endif
    }

    private func beginBackgroundPauseTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "EmbyPlayerBackgroundPause") { [weak self] in
            DispatchQueue.main.async {
                self?.endBackgroundPauseTask()
            }
        }
    }

    private func endBackgroundPauseTaskSoon() {
        endBackgroundPauseTask(after: 1.0)
    }

    private func endBackgroundPauseTaskBeforeExpiration() {
        endBackgroundPauseTask(after: 20.0)
    }

    private func endBackgroundPauseTask(after delay: TimeInterval) {
        guard backgroundTask != .invalid else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.endBackgroundPauseTask()
        }
    }

    private func endBackgroundPauseTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func activatePlaybackAudioSession(reason: String) {
        Task.detached(priority: .userInitiated) {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playback, mode: .moviePlayback)
                try audioSession.setActive(true)
                await MainActor.run {
                    UIApplication.shared.beginReceivingRemoteControlEvents()
                }
                #if DEBUG
                NSLog(
                    "EmbyPlayerAudioSession active=true reason=%@ category=%@ mode=%@",
                    reason,
                    audioSession.category.rawValue,
                    audioSession.mode.rawValue
                )
                #endif
            } catch {
                NSLog("EmbyPlayerAudioSession active=false reason=%@ error=%@", reason, error.localizedDescription)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didRequestClose else { return }
        updateRenderedSubtitleTransform()
        player.refreshVideoRect()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        tracePlayerExit(
            "viewWillTransition begin size=\(Int(size.width))x\(Int(size.height)) duration=\(String(format: "%.3f", coordinator.transitionDuration))"
        )
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.tracePlayerExit("viewWillTransition complete cancelled=\(coordinator.isCancelled)")
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
            self?.scheduleVideoRectRefreshBurst()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tracePlayerExit("viewWillDisappear animated=\(animated)")
        tracePlayerExitLayerState("viewWillDisappear")
        tracePlayerExitTransitionCoordinator("viewWillDisappear")
        if didRequestClose,
           UIApplication.shared.applicationState == .active,
           !isInBackground
        {
            shutdownImmediatelyForPlayerDismissalIfNeeded(reason: "viewWillDisappear")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        tracePlayerExit("viewDidDisappear animated=\(animated)")
        tracePlayerExitLayerState("viewDidDisappear")
        stopHardwareVolumePolling()
        persistSubtitleAdjustmentSettingsNow()
        closeEpisodeListForPlayerDismissal()
        guard UIApplication.shared.applicationState == .active, !isInBackground else {
            isInBackground = true
            return
        }
        onDidDisappear?()
        shutdownImmediatelyForPlayerDismissalIfNeeded(reason: "viewDidDisappear")
        if !usesManualWindowPresentation {
            Self.finalizePortraitOrientationAfterDismissal()
        }
        stopAfterDismissAnimationIfNeeded(reason: "viewDidDisappear")
    }

    private func requestLandscapeOrientation() {
        guard UIDevice.isPhone else { return }

        let generation = Self.prepareLandscapeOrientationForPresentation(requestSceneImmediately: false)
        refreshSupportedOrientations()

        let scenes: [UIWindowScene]
        if let scene = view.window?.windowScene {
            scenes = [scene]
        } else {
            scenes = Self.foregroundWindowScenes
        }

        guard scenes.isNotEmpty else {
            NSLog("EmbyPlayerOrientation request=landscape result=missing-window-scene")
            return
        }

        pendingLandscapeRequestWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.didRequestClose else { return }
            guard generation == Self.orientationOverrideGeneration else { return }
            self.refreshSupportedOrientations()
            scenes.forEach { scene in
                self.requestSceneOrientation(.landscapeRight, on: scene, logName: "landscape")
            }
        }
        pendingLandscapeRequestWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    @discardableResult
    static func prepareLandscapeOrientationForPresentation(requestSceneImmediately: Bool = true) -> Int {
        guard UIDevice.isPhone else { return orientationOverrideGeneration }

        let isAlreadyPrepared = AppDelegate.phoneOrientationLock == .landscape &&
            UIPreferencesHostingController.globalSupportedOrientationsOverride == .landscape &&
            UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride == .landscapeRight
        if isAlreadyPrepared {
            let generation = orientationOverrideGeneration
            Self.refreshAllSupportedOrientations()
            if requestSceneImmediately {
                DispatchQueue.main.async {
                    guard generation == orientationOverrideGeneration else { return }
                    Self.foregroundWindowScenes.forEach { scene in
                        Self.requestSceneOrientation(.landscapeRight, on: scene, logName: "landscape-prepare")
                    }
                }
            }
            return generation
        }

        orientationOverrideGeneration += 1
        let generation = orientationOverrideGeneration
        AppDelegate.phoneOrientationLock = .landscape
        UIPreferencesHostingController.globalSupportedOrientationsOverride = .landscape
        UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride = .landscapeRight
        Self.refreshAllSupportedOrientations()
        if requestSceneImmediately {
            Self.foregroundWindowScenes.forEach { scene in
                Self.requestSceneOrientation(.landscapeRight, on: scene, logName: "landscape-prepare")
            }
        }
        #if DEBUG
        NSLog(
            "EmbyPlayerOrientation prepare=landscape generation=%d requestScene=%@",
            generation,
            requestSceneImmediately.description
        )
        #endif
        return generation
    }

    static func requestLandscapeOrientationForPresentationTransition() {
        guard UIDevice.isPhone else { return }

        DispatchQueue.main.async {
            guard AppDelegate.phoneOrientationLock == .landscape else { return }
            Self.foregroundWindowScenes.forEach { scene in
                Self.requestSceneOrientation(.landscapeRight, on: scene, logName: "landscape-present")
            }
        }
    }

    static func finalizePortraitOrientationAfterDismissal() {
        guard UIDevice.isPhone else { return }

        orientationOverrideGeneration += 1
        let generation = orientationOverrideGeneration
        let needsPortraitRequest = foregroundWindowScenes.contains { $0.interfaceOrientation != .portrait }
        applyPortraitOrientationForDismissal(requestSceneImmediately: needsPortraitRequest)

        if needsPortraitRequest {
            DispatchQueue.main.async {
                guard generation == orientationOverrideGeneration else { return }
                Self.requestPortraitSceneOrientationForCurrentGeneration(generation, logName: "portrait-final")
            }

            [0.08, 0.18, 0.32].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard generation == orientationOverrideGeneration else { return }
                    Self.applyPortraitOrientationForDismissal(requestSceneImmediately: false)
                    Self.requestPortraitSceneOrientationForCurrentGeneration(generation, logName: "portrait-final")
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard generation == orientationOverrideGeneration else { return }
            AppDelegate.phoneOrientationLock = nil
            UIPreferencesHostingController.globalSupportedOrientationsOverride = nil
            UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride = nil
            Self.refreshAllSupportedOrientations()
        }

    }

    static func beginPortraitOrientationForDismissal() {
        guard UIDevice.isPhone else { return }

        if AppDelegate.phoneOrientationLock == .portrait,
           UIPreferencesHostingController.globalSupportedOrientationsOverride == .portrait,
           UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride == .portrait
        {
            preparePortraitOrientationForDismissal(requestSceneImmediately: true, logName: "portrait-dismiss")
            return
        }

        orientationOverrideGeneration += 1

        #if DEBUG
        NSLog("EmbyPlayerOrientation begin=portrait-dismiss generation=%d", orientationOverrideGeneration)
        #endif

        preparePortraitOrientationForDismissal(requestSceneImmediately: true, logName: "portrait-dismiss")
    }

    private static func preparePortraitOrientationForDismissal(
        requestSceneImmediately: Bool = true,
        logName: String = "portrait-dismiss"
    ) {
        AppDelegate.phoneOrientationLock = .portrait
        UIPreferencesHostingController.globalSupportedOrientationsOverride = .portrait
        UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride = .portrait
        Self.applyPortraitOrientationOverridesToAllHosts()
        Self.refreshAllSupportedOrientations()
        UIViewController.attemptRotationToDeviceOrientation()
        guard requestSceneImmediately else { return }
        Self.requestPortraitSceneOrientationForCurrentGeneration(
            orientationOverrideGeneration,
            logName: logName
        )
    }

    private static func applyPortraitOrientationForDismissal(
        requestSceneImmediately: Bool = true,
        logName: String = "portrait-final"
    ) {
        AppDelegate.phoneOrientationLock = .portrait
        UIPreferencesHostingController.globalSupportedOrientationsOverride = .portrait
        UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride = .portrait
        Self.applyPortraitOrientationOverridesToAllHosts()
        Self.refreshAllSupportedOrientations()
        UIViewController.attemptRotationToDeviceOrientation()
        guard requestSceneImmediately else { return }
        Self.requestPortraitSceneOrientationForCurrentGeneration(
            orientationOverrideGeneration,
            logName: logName
        )
    }

    private static func applyPortraitOrientationOverridesToAllHosts() {
        foregroundWindowScenes
            .flatMap(\.windows)
            .forEach { window in
                applyPortraitOrientationOverrides(in: window.rootViewController)
            }
    }

    private static var foregroundWindowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    }

    private static func scheduleDismissalOrientationCleanup(for generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard generation == orientationOverrideGeneration else { return }
            AppDelegate.phoneOrientationLock = nil
            UIPreferencesHostingController.globalSupportedOrientationsOverride = nil
            UIPreferencesHostingController.globalPreferredInterfaceOrientationOverride = nil
            Self.refreshAllSupportedOrientations()
        }
    }

    private static func applyPortraitOrientationOverrides(in controller: UIViewController?) {
        guard let controller else { return }

        if let preferencesHost = controller as? UIPreferencesHostingController {
            preferencesHost.supportedOrientationsOverride = UIPreferencesHostingController.globalSupportedOrientationsOverride
            preferencesHost.preferredInterfaceOrientationOverride = .portrait
        }

        controller.children.forEach { applyPortraitOrientationOverrides(in: $0) }
        applyPortraitOrientationOverrides(in: controller.presentedViewController)
    }

    private static func requestPortraitSceneOrientationForCurrentGeneration(
        _ generation: Int,
        logName: String
    ) {
        guard generation == orientationOverrideGeneration else { return }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                Self.requestSceneOrientation(.portrait, on: scene, logName: logName)
            }
    }

    private func refreshSupportedOrientations() {
        var controller: UIViewController? = self
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.parent
        }

        view.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        view.window?.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func refreshAllSupportedOrientations() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                refreshSupportedOrientations(in: window.rootViewController)
            }
    }

    private static func refreshSupportedOrientations(in controller: UIViewController?) {
        guard let controller else { return }

        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        controller.children.forEach { refreshSupportedOrientations(in: $0) }
        refreshSupportedOrientations(in: controller.presentedViewController)
    }

    private static func requestSceneOrientation(
        _ mask: UIInterfaceOrientationMask,
        on scene: UIWindowScene,
        logName: String
    ) {
        #if DEBUG
        let requestStart = CACurrentMediaTime()
        NSLog(
            "EmbyPlayerExitTrace orientation-request-begin name=%@ mask=%@ current=%d",
            logName,
            String(describing: mask),
            scene.interfaceOrientation.rawValue
        )
        #endif
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                NSLog("EmbyPlayerOrientation request=%@ result=fail error=%@", logName, error.localizedDescription)
            }
        } else {
            let orientation: UIInterfaceOrientation = mask == .portrait ? .portrait : .landscapeRight
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }

        NSLog("EmbyPlayerOrientation request=%@ result=sent sceneOrientation=%d", logName, scene.interfaceOrientation.rawValue)
        #if DEBUG
        NSLog(
            "EmbyPlayerExitTrace orientation-request-sent name=%@ elapsed=%.3f current=%d",
            logName,
            CACurrentMediaTime() - requestStart,
            scene.interfaceOrientation.rawValue
        )
        #endif
    }

    private func requestSceneOrientation(
        _ mask: UIInterfaceOrientationMask,
        on scene: UIWindowScene,
        logName: String
    ) {
        Self.requestSceneOrientation(mask, on: scene, logName: logName)
    }

    private func startPlayerExitTrace(reason: String) {
        #if DEBUG
        exitTraceGeneration += 1
        let generation = exitTraceGeneration
        let now = CACurrentMediaTime()
        exitTraceStartTime = now
        exitTraceLastTickTime = now
        NSLog("EmbyPlayerExitTrace start reason=%@", reason)
        tracePlayerExitLayerState("start")
        schedulePlayerExitTraceTick(generation: generation)
        #endif
    }

    private func schedulePlayerExitTraceTick(generation: Int) {
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard self.exitTraceGeneration == generation, self.didRequestClose else { return }
            guard self.view.window != nil else {
                self.tracePlayerExit("tick-stop no-window")
                return
            }

            let now = CACurrentMediaTime()
            let previousTick = self.exitTraceLastTickTime ?? now
            let gap = now - previousTick
            self.exitTraceLastTickTime = now
            let elapsed = self.exitTraceStartTime.map { now - $0 } ?? -1
            if elapsed <= 0.5 || Int((elapsed * 100).rounded()) % 25 == 0 {
                self.tracePlayerExit("tick gap=\(String(format: "%.3f", gap))")
            }
            if gap > 0.12 {
                self.tracePlayerExit("main-thread-gap gap=\(String(format: "%.3f", gap))")
            }
            self.schedulePlayerExitTraceTick(generation: generation)
        }
        #endif
    }

    private func tracePlayerExit(_ message: String) {
        #if DEBUG
        let elapsed = exitTraceStartTime.map { CACurrentMediaTime() - $0 } ?? -1
        let sceneOrientation = view.window?.windowScene?.interfaceOrientation.rawValue ?? 0
        NSLog(
            "EmbyPlayerExitTrace t=%.3f %@ window=%@ sceneOrientation=%d appState=%ld",
            elapsed,
            message,
            (view.window != nil).description,
            sceneOrientation,
            UIApplication.shared.applicationState.rawValue
        )
        #endif
    }

    private func tracePlayerExitTransitionCoordinator(_ source: String) {
        #if DEBUG
        guard let coordinator = transitionCoordinator else {
            tracePlayerExit("\(source) transitionCoordinator=nil")
            return
        }

        tracePlayerExit(
            "\(source) transitionCoordinator duration=\(String(format: "%.3f", coordinator.transitionDuration)) animated=\(coordinator.isAnimated) interactive=\(coordinator.isInteractive)"
        )
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            self?.tracePlayerExit(
                "\(source) transitionCompletion cancelled=\(context.isCancelled) percent=\(String(format: "%.3f", context.percentComplete))"
            )
            self?.tracePlayerExitLayerState("\(source)-transitionCompletion")
        }
        coordinator.notifyWhenInteractionChanges { [weak self] context in
            self?.tracePlayerExit(
                "\(source) interactionChanges cancelled=\(context.isCancelled) percent=\(String(format: "%.3f", context.percentComplete))"
            )
        }
        #endif
    }

    private func tracePlayerExitLayerState(_ source: String) {
        #if DEBUG
        let viewAnimations = view.layer.animationKeys()?.joined(separator: ",") ?? "<none>"
        let playerAnimations = playerView.layer.animationKeys()?.joined(separator: ",") ?? "<none>"
        let metalAnimations = playerView.metalLayer.animationKeys()?.joined(separator: ",") ?? "<none>"
        let root = view.window?.rootViewController
        NSLog(
            "EmbyPlayerExitTrace layer source=%@ isBeingDismissed=%@ movingFromParent=%@ presenting=%@ presented=%@ rootPresented=%@ viewAnim=%@ playerAnim=%@ metalAnim=%@",
            source,
            isBeingDismissed.description,
            isMovingFromParent.description,
            (presentingViewController != nil).description,
            (presentedViewController != nil).description,
            (root?.presentedViewController != nil).description,
            viewAnimations,
            playerAnimations,
            metalAnimations
        )
        #endif
    }

    private func closePlayer() {
        guard !didRequestClose else { return }
        startPlayerExitTrace(reason: "closePlayer")
        tracePlayerExit("closePlayer begin")
        didRequestClose = true
        pendingLandscapeRequestWorkItem?.cancel()
        pendingLandscapeRequestWorkItem = nil
        cancelSubtitleAdjustmentReapply()
        persistSubtitleAdjustmentSettingsNow()
        setBufferingIndicatorVisible(false, animated: false)
        hidePlayerViewForImmediateDismissal()
        tracePlayerExitLayerState("after-hidePlayerView")
        prepareForSimultaneousPortraitDismissal()
        cancelControlsHide()
        hideSeekPreviewNow()
        hideGestureHUDNow()
        closeEpisodeListForPlayerDismissal()
        if controlsView.needsSubtitleAdjustmentDismissalForPlayerDismissal {
            tracePlayerExit("closePlayer closeSubtitleAdjustment")
            controlsView.closeSubtitleAdjustmentForPlayerDismissal()
        }
        player.setMuted(true)
        if usesManualWindowPresentation {
            tracePlayerExit("closePlayer onClose fire immediate-window")
            onClose?()
            Notifications[.willDismissVideoPlayer].post()
            return
        }
        stopTransportForPlayerDismissalIfNeeded(reason: "closePlayer")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didRequestClose, self.view.window != nil else { return }
            self.tracePlayerExit("closePlayer onClose fire")
            self.onClose?()
            Notifications[.willDismissVideoPlayer].post()
        }
        tracePlayerExit("closePlayer scheduledOnClose")
    }

    private func hidePlayerViewForImmediateDismissal() {
        tracePlayerExit("hidePlayerView begin")
        UIView.performWithoutAnimation {
            view.isUserInteractionEnabled = false
            view.isOpaque = false
            view.backgroundColor = .clear

            playerView.layer.removeAllAnimations()
            playerView.metalLayer.removeAllAnimations()
            playerView.alpha = 0
            playerView.isHidden = true
            playerView.layer.isHidden = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerView.metalLayer.opacity = 0
            CATransaction.commit()

            controlsView.layer.removeAllAnimations()
            controlsView.alpha = 0
            controlsView.isHidden = true

            renderedSubtitleLabel.layer.removeAllAnimations()
            renderedSubtitleLabel.alpha = 0
            renderedSubtitleLabel.isHidden = true
        }
        tracePlayerExit("hidePlayerView end")
    }

    private func prepareForSimultaneousPortraitDismissal() {
        guard UIDevice.isPhone else { return }
        guard !usesManualWindowPresentation else { return }

        tracePlayerExit("preparePortrait begin")
        Self.beginPortraitOrientationForDismissal()
        refreshSupportedOrientations()
        tracePlayerExit("preparePortrait end")
    }

    @objc private nonisolated func appDidEnterBackgroundNotification() {
        Task { @MainActor [weak self] in
            self?.handleAppDidEnterBackground()
        }
    }

    @objc private nonisolated func appWillEnterForegroundNotification() {
        Task { @MainActor [weak self] in
            self?.handleAppWillEnterForeground()
        }
    }

    @objc private nonisolated func appDidBecomeActiveNotification() {
        Task { @MainActor [weak self] in
            self?.handleAppDidBecomeActive()
        }
    }

    private func handleAppDidEnterBackground() {
        isInBackground = true
        UIApplication.shared.isIdleTimerDisabled = false

        let playsInBackground = Defaults[.VideoPlayer.Transition.pauseOnBackground]
        let shouldPause = !playsInBackground
        shouldResumeAfterForeground = shouldPause && !player.isPaused
        if shouldPause {
            beginBackgroundPauseTaskIfNeeded()
            player.setPaused(true)
        } else {
            activatePlaybackAudioSession(reason: "didEnterBackground")
            endBackgroundPauseTask()
        }

        #if DEBUG
        NSLog("EmbyPlayerBackground didEnter playInBackground=%@ pause=%@ resume=%@ time=%.3f remaining=%.1f",
              playsInBackground.description,
              shouldPause.description,
              shouldResumeAfterForeground.description,
              player.currentTime,
              UIApplication.shared.backgroundTimeRemaining)
        #endif

        if shouldPause {
            endBackgroundPauseTaskSoon()
        }
    }

    private func handleAppWillEnterForeground() {
        isInBackground = false
        endBackgroundPauseTask()
        foregroundResumeBeganAt = Date()
        foregroundGeometryLogUntil = Date().addingTimeInterval(2)
        didLogForegroundTimeAdvance = false

        view.setNeedsLayout()
        view.layoutIfNeeded()
        playerView.refreshRenderingSurfaceForForeground()
        scheduleForegroundRenderRefreshBurst(nudgeVideoOutput: true)

        if shouldResumeAfterForeground {
            shouldResumeAfterForeground = false
            player.setPaused(false)
            UIApplication.shared.isIdleTimerDisabled = true
        }

        #if DEBUG
        NSLog("EmbyPlayerBackground willEnterForeground resumed=%@ time=%.3f drawable=%@",
              (!player.isPaused).description,
              player.currentTime,
              NSCoder.string(for: playerView.metalLayer.drawableSize))
        logForegroundGeometry(reason: "willEnterForeground")
        #endif
    }

    private func handleAppDidBecomeActive() {
        guard !didRequestClose else { return }
        isInBackground = false
        scheduleForegroundRenderRefreshBurst(nudgeVideoOutput: false)

        #if DEBUG
        NSLog("EmbyPlayerBackground didBecomeActive bounds=%@ drawable=%@",
              NSCoder.string(for: playerView.bounds),
              NSCoder.string(for: playerView.metalLayer.drawableSize))
        logForegroundGeometry(reason: "didBecomeActive")
        #endif
    }

    #if DEBUG
    @objc private func debugPlaybackSmokeCloseRequested() {
        if opensSubtitleAdjustmentBeforeSmokeClose {
            controlsView.showSubtitleAdjustmentPanel(mode: .position, animated: false)
        }
        closePlayer()
    }

    @objc private func debugPlaybackSmokeNextRequested() {
        controlsView.onNextEpisode?()
    }

    @objc private func debugPlaybackSmokePreviousRequested() {
        controlsView.onPreviousEpisode?()
    }

    @objc private func debugPlaybackSmokeVerifyLongPressHUDRequested() {
        showControls()
        let initialSpeed = player.playbackSpeed
        handleLongPressSpeedGesture(state: .began)
        let controlsVisibleImmediatelyAfterBegin = controlsView.controlsVisibleForSmoke

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let visibleAfterBegin = self.controlsView.gestureHUDVisibleForSmoke
            let textAfterBegin = self.controlsView.gestureHUDTextForSmoke
            let controlsVisibleAfterBegin = self.controlsView.controlsVisibleForSmoke

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { [weak self] in
                guard let self else { return }
                let visibleWhileHeldAfterDelay = self.controlsView.gestureHUDVisibleForSmoke
                let controlsVisibleWhileHeldAfterDelay = self.controlsView.controlsVisibleForSmoke
                self.handleLongPressSpeedGesture(state: .ended)
                let currentSpeed = self.player.playbackSpeed
                let passed = visibleAfterBegin &&
                    textAfterBegin.isNotEmpty &&
                    !controlsVisibleImmediatelyAfterBegin &&
                    !controlsVisibleAfterBegin &&
                    !visibleWhileHeldAfterDelay &&
                    !controlsVisibleWhileHeldAfterDelay &&
                    abs(currentSpeed - initialSpeed) < 0.001
                let detail = "visibleAfterBegin=\(visibleAfterBegin) text=\(textAfterBegin) controlsVisibleImmediatelyAfterBegin=\(controlsVisibleImmediatelyAfterBegin) controlsVisibleAfterBegin=\(controlsVisibleAfterBegin) visibleWhileHeldAfterDelay=\(visibleWhileHeldAfterDelay) controlsVisibleWhileHeldAfterDelay=\(controlsVisibleWhileHeldAfterDelay) speed=\(String(format: "%.2f", currentSpeed))"

                NSLog("EmbyPlayerGestureHUDSmoke %@", detail)
                NotificationCenter.default.post(
                    name: .debugPlaybackSmokeLongPressHUDVerified,
                    object: nil,
                    userInfo: [
                        "passed": passed,
                        "detail": detail
                    ]
                )
            }
        }
    }

    @objc private func debugPlaybackSmokeVerifyProgressBarAutoHideRequested() {
        showControls()
        let target = controlsView.triggerSliderDragForSmoke(toFraction: 0.62)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { [weak self] in
            guard let self else { return }
            let progressVisibleAfterDelay = self.controlsView.progressControlsVisibleForSmoke
            let controlsVisibleAfterDelay = self.controlsView.controlsVisibleForSmoke
            let passed = !progressVisibleAfterDelay && !controlsVisibleAfterDelay
            let detail = "target=\(String(format: "%.2f", target)) progressVisibleAfterDelay=\(progressVisibleAfterDelay) controlsVisibleAfterDelay=\(controlsVisibleAfterDelay)"

            NSLog("EmbyPlayerProgressBarAutoHideSmoke %@", detail)
            NotificationCenter.default.post(
                name: .debugPlaybackSmokeProgressBarAutoHideVerified,
                object: nil,
                userInfo: [
                    "passed": passed,
                    "detail": detail
                ]
            )
        }
    }

    @objc private func debugPlaybackSmokeVerifySeekGestureHUDRequested() {
        showControls()
        let expectedTimelineValue = targetTime(forSeekDelta: 12)
        handleSeekGesture(delta: 12, state: .changed)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let visibleAfterChange = self.controlsView.gestureHUDVisibleForSmoke
            let textAfterChange = self.controlsView.gestureHUDTextForSmoke
            let usesPlainTopStyle = self.controlsView.gestureHUDUsesPlainTopStyleForSmoke
            let legacySeekPreviewVisible = self.controlsView.seekPreviewVisibleForSmoke
            let timelineValueAfterChange = self.controlsView.timelineValueForSmoke
            let timelineTracksTarget = abs(timelineValueAfterChange - expectedTimelineValue) < 0.5

            self.handleSeekGesture(delta: 12, state: .ended)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
                guard let self else { return }
                let visibleAfterDelay = self.controlsView.gestureHUDVisibleForSmoke
                let passed = visibleAfterChange &&
                    textAfterChange.isNotEmpty &&
                    usesPlainTopStyle &&
                    !legacySeekPreviewVisible &&
                    timelineTracksTarget &&
                    !visibleAfterDelay
                let detail = "visibleAfterChange=\(visibleAfterChange) text=\(textAfterChange) usesPlainTopStyle=\(usesPlainTopStyle) legacySeekPreviewVisible=\(legacySeekPreviewVisible) timelineValueAfterChange=\(String(format: "%.2f", timelineValueAfterChange)) expectedTimelineValue=\(String(format: "%.2f", expectedTimelineValue)) timelineTracksTarget=\(timelineTracksTarget) visibleAfterDelay=\(visibleAfterDelay)"

                NSLog("EmbyPlayerSeekGestureHUDSmoke %@", detail)
                NotificationCenter.default.post(
                    name: .debugPlaybackSmokeSeekGestureHUDVerified,
                    object: nil,
                    userInfo: [
                        "passed": passed,
                        "detail": detail
                    ]
                )
            }
        }
    }

    private func startSubtitleBorderExerciseForSmokeIfNeeded() {
        guard exercisesSubtitleBorderForSmoke, !didStartSubtitleBorderExerciseForSmoke else { return }
        didStartSubtitleBorderExerciseForSmoke = true
        let values = [0.0, 2.0, 4.0, 6.0, 3.5]
        for (index, value) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(index) * 0.45) { [weak self] in
                guard let self else { return }
                self.setSubtitleBorderSize(value)
                NSLog("EmbyPlayerSubtitleBorderExercise value=%.2f", value)
            }
        }
    }

    private func startSubtitleScaleExerciseForSmokeIfNeeded() {
        guard exercisesSubtitleScaleForSmoke, !didStartSubtitleScaleExerciseForSmoke else { return }
        didStartSubtitleScaleExerciseForSmoke = true
        let values = [1.0, 1.4, 2.0, 0.8, 1.4]
        for (index, value) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(index) * 0.45) { [weak self] in
                guard let self else { return }
                self.setSubtitleScale(value)
                NSLog("EmbyPlayerSubtitleScaleExercise value=%.2f position=%.2f", value, self.subtitlePosition)
            }
        }
    }
    #endif

    deinit {
        NotificationCenter.default.removeObserver(self)
        episodeListLoadTask?.cancel()
        volumePollingTimer?.invalidate()
        reapplySubtitleAdjustmentWorkItem?.cancel()
        persistSubtitleAdjustmentWorkItem?.cancel()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        UIApplication.shared.isIdleTimerDisabled = false
        player.shutdown()
    }

    func play() {
        player.setPaused(false)
    }

    func pause() {
        player.setPaused(true)
    }

    func stop() {
        stopImmediatelyForPlayerTeardown()
    }

    private func stopImmediatelyForPlayerTeardown() {
        guard !didStopPlayback else { return }
        didStopPlayback = true
        updateRenderedSubtitle(nil)
        player.stop()
        isBuffering.value = false
        UIApplication.shared.isIdleTimerDisabled = false
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    private func stopTransportForPlayerDismissalIfNeeded(reason: String) {
        guard !didStopPlayback else { return }
        didStopPlayback = true

        updateRenderedSubtitle(nil)
        player.stop()
        isBuffering.value = false
        UIApplication.shared.isIdleTimerDisabled = false
        UIApplication.shared.endReceivingRemoteControlEvents()

        #if DEBUG
        NSLog("EmbyPlayerTransportStop reason=%@", reason)
        #endif
    }

    func stopForSwiftUIDismantleIfNeeded() {
        guard UIApplication.shared.applicationState == .active, !isInBackground else {
            isInBackground = true
            return
        }
        shutdownImmediatelyForPlayerDismissalIfNeeded(reason: "swiftui-dismantle")
        stopAfterDismissAnimationIfNeeded(reason: "swiftui-dismantle")
    }

    private func shutdownImmediatelyForPlayerDismissalIfNeeded(reason: String) {
        guard !didShutdownForDismissal else { return }
        didShutdownForDismissal = true
        didStopPlayback = true

        updateRenderedSubtitle(nil)
        player.setMuted(true)
        player.shutdown()
        isBuffering.value = false
        UIApplication.shared.isIdleTimerDisabled = false
        UIApplication.shared.endReceivingRemoteControlEvents()

        #if DEBUG
        NSLog("EmbyPlayerTeardown shutdown reason=%@", reason)
        #endif
    }

    private func stopAfterDismissAnimationIfNeeded(reason: String) {
        guard !didScheduleDeferredStop else { return }
        didScheduleDeferredStop = true

        let retainedManager = manager
        #if DEBUG
        NSLog("EmbyPlayerDeferredStop schedule reason=%@", reason)
        #endif

        let delay: TimeInterval = didRequestClose ? 0 : 1.15
        let stopAction = {
            #if DEBUG
            NSLog("EmbyPlayerDeferredStop fire reason=%@", reason)
            #endif
            if let retainedManager {
                retainedManager.stop()
            } else {
                self.stopImmediatelyForPlayerTeardown()
            }
        }

        if delay <= 0 {
            DispatchQueue.main.async {
                stopAction()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                stopAction()
            }
        }
    }

    func jumpForward(_ seconds: Duration) {
        let remaining: Duration
        if let runtime = manager?.item.runtime, let current = manager?.seconds {
            remaining = max(.zero, runtime - current)
        } else {
            remaining = seconds
        }

        let target = min(seconds, remaining)
        guard target > .zero else { return }
        player.seek(by: target.seconds)
    }

    func jumpBackward(_ seconds: Duration) {
        player.seek(by: -seconds.seconds)
    }

    func setRate(_ rate: Float) {
        player.setPlaybackSpeed(Double(rate))
        controlsView.updatePlaybackSpeed(Double(rate))
    }

    func setSeconds(_ seconds: Duration) {
        player.seek(to: seconds.seconds)
    }

    func setAspectFill(_ aspectFill: Bool) {
        playerView.contentMode = aspectFill ? .scaleAspectFill : .scaleAspectFit
    }

    func setAudioStream(_ stream: MediaStream) {
        guard let trackID = mpvTrackID(for: stream, in: manager?.playbackItem?.audioStreams ?? []) else { return }
        #if DEBUG
        NSLog("EmbyPlayerAudioSelect embyIndex=%d originalIndex=%d mpvID=%@",
              stream.index ?? -1,
              stream.originalIndex ?? -1,
              trackID)
        #endif
        player.selectAudioTrack(id: trackID)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        guard (stream.index ?? stream.originalIndex ?? -1) >= 0 else {
            player.disableSubtitle()
            updateRenderedSubtitle(nil)
            return
        }

        guard let trackID = mpvTrackID(for: stream, in: manager?.playbackItem?.subtitleStreams ?? []) else { return }
        #if DEBUG
        NSLog("EmbyPlayerSubtitleSelect embyIndex=%d originalIndex=%d mpvID=%@",
              stream.index ?? -1,
              stream.originalIndex ?? -1,
              trackID)
        #endif
        player.selectSubtitleTrack(id: trackID)
    }

    func setAudioOffset(_ seconds: Duration) {}
    func setSubtitleOffset(_ seconds: Duration) {
        setSubtitleDelay(seconds.seconds)
    }
    func setSubtitleColor(_ color: Color) {}
    func setSubtitleFontName(_ fontName: String) {}
    func setSubtitleFontSize(_ fontSize: Int) {
        let scale = Double(fontSize) / 28.0
        setSubtitleScale(scale)
    }

    private func prepareVideoSurfaceForLoading() {
        isWaitingForFirstVideoFrame = true
        view.isOpaque = true
        view.backgroundColor = .embyAppBackgroundSurface
        playerView.layer.isHidden = false
        playerView.isHidden = false
        playerView.alpha = 0
        playerView.isOpaque = true
        playerView.backgroundColor = .embyAppBackgroundSurface
        playerView.metalLayer.isOpaque = false
        playerView.metalLayer.opacity = 0
    }

    private func revealVideoSurfaceForPlayback() {
        guard !didRequestClose else { return }
        guard isWaitingForFirstVideoFrame || playerView.alpha < 1 else { return }
        isWaitingForFirstVideoFrame = false

        view.isOpaque = false
        view.backgroundColor = .clear
        playerView.layer.isHidden = false
        playerView.isHidden = false
        playerView.isOpaque = true
        playerView.backgroundColor = .black
        playerView.metalLayer.isOpaque = true
        playerView.metalLayer.opacity = 1

        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.playerView.alpha = 1
        }
    }

    private func installViews() {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        renderedSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
        episodeListPanel.translatesAutoresizingMaskIntoConstraints = false
        episodeListTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        episodeListTableView.translatesAutoresizingMaskIntoConstraints = false
        episodeListLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        configureBufferingIndicator()
        configureRenderedSubtitleOverlay()
        configureEpisodeListPanel()

        view.addSubview(playerView)
        view.addSubview(controlsView)
        view.addSubview(bufferingIndicator)
        view.addSubview(renderedSubtitleLabel)
        view.addSubview(episodeListPanel)

        let subtitleVisibleBottomConstraint = renderedSubtitleLabel.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -34
        )
        let subtitleControlsBottomConstraint = renderedSubtitleLabel.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -128
        )
        self.subtitleVisibleBottomConstraint = subtitleVisibleBottomConstraint
        self.subtitleControlsBottomConstraint = subtitleControlsBottomConstraint

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bufferingIndicator.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),

            episodeListPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            episodeListPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            episodeListPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -96),
            episodeListPanel.heightAnchor.constraint(equalToConstant: 250),

            episodeListTitleLabel.leadingAnchor.constraint(equalTo: episodeListPanel.contentView.leadingAnchor, constant: 18),
            episodeListTitleLabel.trailingAnchor.constraint(equalTo: episodeListLoadingIndicator.leadingAnchor, constant: -12),
            episodeListTitleLabel.topAnchor.constraint(equalTo: episodeListPanel.contentView.topAnchor, constant: 14),
            episodeListLoadingIndicator.centerYAnchor.constraint(equalTo: episodeListTitleLabel.centerYAnchor),
            episodeListLoadingIndicator.trailingAnchor.constraint(equalTo: episodeListPanel.contentView.trailingAnchor, constant: -18),
            episodeListTableView.leadingAnchor.constraint(equalTo: episodeListPanel.contentView.leadingAnchor),
            episodeListTableView.trailingAnchor.constraint(equalTo: episodeListPanel.contentView.trailingAnchor),
            episodeListTableView.topAnchor.constraint(equalTo: episodeListTitleLabel.bottomAnchor, constant: 8),
            episodeListTableView.bottomAnchor.constraint(equalTo: episodeListPanel.contentView.bottomAnchor, constant: -8),

            renderedSubtitleLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            renderedSubtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 54),
            renderedSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -54),
            renderedSubtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.82),
            subtitleControlsBottomConstraint
        ])
    }

    private func configureBufferingIndicator() {
        bufferingIndicator.alpha = 0
        bufferingIndicator.isHidden = true
        bufferingIndicator.hidesWhenStopped = false
        bufferingIndicator.color = .white
        bufferingIndicator.accessibilityIdentifier = "emby-player-buffering-indicator"
        bufferingIndicator.layer.zPosition = 12_000
        bufferingIndicator.layer.shadowColor = UIColor.black.cgColor
        bufferingIndicator.layer.shadowOpacity = 0.75
        bufferingIndicator.layer.shadowRadius = 5
        bufferingIndicator.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func configureRenderedSubtitleOverlay() {
        renderedSubtitleLabel.alpha = 0
        renderedSubtitleLabel.isUserInteractionEnabled = false
        renderedSubtitleLabel.backgroundColor = .clear
        renderedSubtitleLabel.textAlignment = .center
        renderedSubtitleLabel.numberOfLines = 3
        renderedSubtitleLabel.lineBreakMode = .byTruncatingTail
        renderedSubtitleLabel.adjustsFontSizeToFitWidth = true
        renderedSubtitleLabel.minimumScaleFactor = 0.72
        renderedSubtitleLabel.accessibilityIdentifier = "emby-rendered-subtitle-overlay"
        renderedSubtitleLabel.layer.zPosition = 10_000
        renderedSubtitleLabel.layer.shadowColor = UIColor.black.cgColor
        renderedSubtitleLabel.layer.shadowOpacity = 0.95
        renderedSubtitleLabel.layer.shadowRadius = 4
        renderedSubtitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        renderedSubtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func configureEpisodeListPanel() {
        episodeListPanel.alpha = 0
        episodeListPanel.isHidden = true
        episodeListPanel.transform = CGAffineTransform(translationX: 0, y: 14)
        episodeListPanel.layer.zPosition = 13_000
        episodeListPanel.clipsToBounds = true
        episodeListPanel.layer.cornerRadius = 24
        episodeListPanel.layer.cornerCurve = .continuous
        episodeListPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        episodeListPanel.layer.borderWidth = 0.5
        episodeListPanel.backgroundColor = .clear
        episodeListPanel.contentView.backgroundColor = Self.menuPanelBackgroundColor
        episodeListPanel.contentView.addSubview(episodeListTitleLabel)
        episodeListPanel.contentView.addSubview(episodeListLoadingIndicator)
        episodeListPanel.contentView.addSubview(episodeListTableView)

        episodeListTitleLabel.text = "选集"
        episodeListTitleLabel.textColor = .white
        episodeListTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        episodeListTitleLabel.adjustsFontSizeToFitWidth = true
        episodeListTitleLabel.minimumScaleFactor = 0.8

        episodeListLoadingIndicator.color = .white
        episodeListLoadingIndicator.hidesWhenStopped = true

        episodeListTableView.backgroundColor = .clear
        episodeListTableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
        episodeListTableView.indicatorStyle = .white
        episodeListTableView.rowHeight = 56
        episodeListTableView.dataSource = self
        episodeListTableView.delegate = self
        episodeListTableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.episodeListCellIdentifier)
        episodeListTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
    }

    private static func panelEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .clear)
            effect.isInteractive = true
            effect.tintColor = UIColor.black.withAlphaComponent(0.22)
            return effect
        }

        return UIBlurEffect(style: .systemUltraThinMaterialDark)
    }

    private static var menuPanelBackgroundColor: UIColor {
        if #available(iOS 26.0, *) {
            return UIColor.black.withAlphaComponent(0.32)
        }

        return UIColor.black.withAlphaComponent(0.18)
    }

    private func installVolumeView() {
        volumeView.showsVolumeSlider = true
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = true
        view.addSubview(volumeView)
        resolveVolumeSlider()
    }

    private func bindHardwareVolumeHUD() {
        lastObservedOutputVolume = Double(AVAudioSession.sharedInstance().outputVolume)
        startHardwareVolumePolling()
    }

    private func startHardwareVolumePolling() {
        guard volumePollingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollHardwareVolume()
            }
        }
        volumePollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHardwareVolumePolling() {
        volumePollingTimer?.invalidate()
        volumePollingTimer = nil
    }

    private func pollHardwareVolume() {
        guard view.window != nil, !didRequestClose else { return }
        let value = Double(AVAudioSession.sharedInstance().outputVolume)
        guard abs(value - lastObservedOutputVolume) >= 0.005 else { return }
        lastObservedOutputVolume = value
        hideSeekPreviewNow()
        presentGestureHUD(symbol: adjustmentSymbol(for: .volume),
                          text: "\(adjustmentTitle(for: .volume)) \(Int((value * 100).rounded()))%",
                          autoHideAfter: 0.8)
    }

    private func bindBufferingIndicator() {
        setBufferingIndicatorVisible(isBuffering.value, animated: false)
        isBuffering.$value
            .removeDuplicates()
            .sink { [weak self] buffering in
                Task { @MainActor in
                    self?.setBufferingIndicatorVisible(buffering, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func setBufferingIndicatorVisible(_ visible: Bool, animated: Bool) {
        guard !didRequestClose || !visible else { return }
        bufferingIndicatorVisibilityGeneration += 1
        let generation = bufferingIndicatorVisibilityGeneration
        guard bufferingIndicatorVisible != visible || bufferingIndicator.isHidden == visible else {
            if visible, !bufferingIndicator.isAnimating {
                bufferingIndicator.startAnimating()
            }
            return
        }

        bufferingIndicatorVisible = visible

        if visible {
            bufferingIndicator.isHidden = false
            bufferingIndicator.startAnimating()
        }

        let changes = {
            self.bufferingIndicator.alpha = visible ? 1 : 0
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.bufferingIndicatorVisibilityGeneration == generation else { return }
            if !visible {
                self.bufferingIndicator.stopAnimating()
                self.bufferingIndicator.isHidden = true
            }
        }

        #if DEBUG
        NSLog("EmbyPlayerBufferingIndicator visible=%@ animated=%@", visible.description, animated.description)
        #endif

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }

    private func bind(manager: MediaPlayerManager) {
        updateTitle(for: manager.item)

        manager.$item
            .sink { [weak self] item in
                Task { @MainActor in
                    self?.updateTitle(for: item)
                }
            }
            .store(in: &cancellables)

        manager.$playbackItem
            .sink { [weak self] playbackItem in
                Task { @MainActor in
                    guard let playbackItem else { return }
                    guard let self else { return }
                    guard self.isReadyToStartPlayback else {
                        self.pendingPlaybackItemForPresentation = playbackItem
                        self.isBuffering.value = true
                        #if DEBUG
                        NSLog("EmbyPlayerPresentation deferPlaybackUntilVisible")
                        #endif
                        return
                    }
                    self.playNew(item: playbackItem)
                }
            }
            .store(in: &cancellables)

        manager.$state
            .sink { [weak self] state in
                Task { @MainActor in
                    if state == .stopped {
                        self?.closePlayer()
                    }
                }
            }
            .store(in: &cancellables)

        manager.$rate
            .sink { [weak self] rate in
                Task { @MainActor in
                    self?.setRate(rate)
                }
            }
            .store(in: &cancellables)

        manager.$queue
            .sink { [weak self] queue in
                Task { @MainActor in
                    self?.bindQueue(queue)
                }
            }
            .store(in: &cancellables)
    }

    private func playPendingPlaybackItemForPresentationIfNeeded() {
        guard let playbackItem = pendingPlaybackItemForPresentation else { return }
        pendingPlaybackItemForPresentation = nil
        isBuffering.value = true
        #if DEBUG
        NSLog("EmbyPlayerPresentation startDeferredPlayback")
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isReadyToStartPlayback, !self.didRequestClose else { return }
            self.playNew(item: playbackItem)
        }
    }

    private func updateTitle(for item: BaseItemDto) {
        let title = item.displayTitle
        let subtitleParts = [
            item.parentTitle,
            item.seasonEpisodeLabel,
        ]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        let subtitle = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
        controlsView.updateTitle(title, subtitle: subtitle)
        updateSkipIntroButtonVisibility(for: item)

        #if DEBUG
        NSLog("EmbyPlayerTitle title=%@ subtitle=%@", title, subtitle ?? "<nil>")
        #endif
    }

    private func updateSkipIntroButtonVisibility(for item: BaseItemDto?) {
        controlsView.updateSkipIntroSeconds(
            SkipIntroDismissalStore.seconds(
                for: item,
                default: Defaults[.VideoPlayer.skipIntroSeconds]
            )
        )
        let shouldHide = !Defaults[.VideoPlayer.showSkipIntroButton]
            || SkipIntroDismissalStore.contains(item: item)
        controlsView.setSkipIntroDismissed(shouldHide)
    }

    private func bindQueue(_ queue: AnyMediaPlayerQueue?) {
        queueCancellable = nil
        updateEpisodeNavigation()

        guard let queue else { return }
        queueCancellable = queue.$nextItem
            .combineLatest(queue.$previousItem)
            .sink { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateEpisodeNavigation()
                }
            }
    }

    private func bindPlayer() {
        player.onTimeChanged = { [weak self] time, duration in
            Task { @MainActor in
                guard let self else { return }
                self.manager?.seconds = Duration.seconds(time)
                if !self.isWaitingForFirstVideoFrame {
                    self.isBuffering.value = false
                }
                self.controlsView.update(time: time, duration: duration)

                #if DEBUG
                if let beganAt = self.foregroundResumeBeganAt, !self.didLogForegroundTimeAdvance, time > 0 {
                    self.didLogForegroundTimeAdvance = true
                    NSLog(
                        "EmbyPlayerBackground foregroundTimeAdvance elapsed=%.3f time=%.3f duration=%.3f",
                        Date().timeIntervalSince(beganAt),
                        time,
                        duration
                    )
                }
                if let resume = self.pendingResumeObservation, duration > 0, time > 0 {
                    let reachedResumePoint = resume.expectedSeconds < 3 || time >= resume.expectedSeconds - 2
                    if reachedResumePoint {
                        NSLog(
                            "EmbyPlayerResumeObserved item=%@ expected=%.3f observed=%.3f duration=%.3f",
                            resume.itemID,
                            resume.expectedSeconds,
                            time,
                            duration
                        )
                        self.pendingResumeObservation = nil
                    }
                }
                #endif
            }
        }

        player.onPausedChanged = { [weak self] paused in
            Task { @MainActor in
                guard let self else { return }
                if paused {
                    self.cancelLongPressSpeedIfNeeded()
                }
                self.controlsView.setPaused(paused)
                self.manager?.setPlaybackRequestStatus(status: paused ? .paused : .playing)
            }
        }

        player.onBufferingChanged = { [weak self] buffering in
            Task { @MainActor in
                guard let self else { return }
                if buffering {
                    self.isBuffering.value = true
                } else if !self.isWaitingForFirstVideoFrame {
                    self.isBuffering.value = false
                }
            }
        }

        player.onCachedTimeChanged = { [weak self] cachedTime in
            Task { @MainActor in
                self?.controlsView.updateCachedTime(cachedTime)
            }
        }

        player.onCacheSpeedChanged = { [weak self] bytesPerSecond in
            Task { @MainActor in
                self?.controlsView.updateCacheSpeed(bytesPerSecond)
            }
        }

        player.onVideoRectChanged = { [weak self] rect in
            Task { @MainActor in
                guard let self else { return }
                self.lastVideoRect = rect
                self.videoSize.value = CGSize(width: rect.width, height: rect.height)
                #if DEBUG
                self.logForegroundGeometry(reason: "videoRectChanged")
                #endif
            }
        }

        player.onFirstFrameRendered = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                #if DEBUG
                if let beganAt = self.foregroundResumeBeganAt {
                    NSLog(
                        "EmbyPlayerBackground foregroundFirstFrame elapsed=%.3f",
                        Date().timeIntervalSince(beganAt)
                    )
                    self.foregroundResumeBeganAt = nil
                }
                #endif
                self.revealVideoSurfaceForPlayback()
                self.isBuffering.value = false
            }
        }

        player.onSubtitleTracksChanged = { [weak self] tracks, selectedID in
            Task { @MainActor in
                guard let self else { return }
                guard !self.didRequestClose else { return }
                self.controlsView.updateSubtitleTracks(tracks, selectedID: selectedID)

                #if DEBUG
                let trackSummary = tracks
                    .map { "\($0.id):\($0.isSelected ? "*" : "-")\($0.title):\($0.codec ?? "<codec>")" }
                    .joined(separator: " | ")
                NSLog(
                    "EmbyPlayerSubtitleTracks count=%d selected=%@ tracks=%@",
                    tracks.count,
                    selectedID ?? "<nil>",
                    trackSummary
                )
                #endif

                if let pendingTitle = self.pendingDefaultExternalSubtitleTitle {
                    if let track = self.pendingDefaultSubtitleTrack(in: tracks, title: pendingTitle) {
                        if selectedID != track.id {
                            self.player.selectSubtitleTrack(id: track.id)
                            self.reapplySubtitleAdjustmentSettings(reason: "pending-default-subtitle-select")
                            #if DEBUG
                            NSLog("EmbyPlayerDefaultExternalSubtitleSelected id=%@ title=%@", track.id, track.title)
                            #endif
                        }
                        self.schedulePendingDefaultExternalSubtitleClear(title: pendingTitle)
                    } else if selectedID != nil {
                        self.player.disableSubtitle()
                        self.updateRenderedSubtitle(nil)
                        #if DEBUG
                        NSLog("EmbyPlayerDefaultExternalSubtitlePending title=%@ action=disable-current", pendingTitle)
                        #endif
                    }
                }
                self.reapplySubtitleAdjustmentSettings(reason: "subtitle-tracks-changed")
                self.scheduleSubtitleAdjustmentReapply(reason: "subtitle-tracks-changed-delayed", after: 0.18)
            }
        }

        player.onSubtitleTextChanged = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard !self.didRequestClose else { return }
                if self.usesSubtitleTextFallback {
                    self.updateRenderedSubtitle(text)
                }
                if self.controlsView.isSubtitleAdjustmentPanelVisible {
                    self.scheduleSubtitleAdjustmentReapply(reason: "subtitle-text-changed", after: 0.12)
                }
            }
        }

        player.onFinished = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.didRequestClose else { return }
                UIApplication.shared.isIdleTimerDisabled = false
                self.controlsView.suppressPausedIndicatorTemporarily()
                self.controlsView.setPaused(true)
                self.showControls()
                guard self.manager?.item.isLiveStream != true else { return }
                if self.manager?.item.userData?.isPlayed != true,
                   SkipIntroDismissalStore.contains(item: self.manager?.item) {
                    SkipIntroDismissalStore.reset(for: self.manager?.item)
                }
                self.updateSkipIntroButtonVisibility(for: self.manager?.item)
                self.manager?.ended()
            }
        }

        player.onError = { [weak self] message in
            Task { @MainActor in
                self?.presentError(message)
                self?.manager?.error(ErrorMessage("libmpv playback error: \(message)"))
            }
        }

        player.onLog = { [weak self] message in
            let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            if self?.logsAllMPVDiagnosticsForSmoke == true {
                NSLog("mpv: %@", line)
            } else if line.contains("level=warn") || line.contains("level=error") || line.contains("level=fatal") {
                NSLog("mpv: %@", line)
            }
            #else
            if line.contains("level=warn") || line.contains("level=error") || line.contains("level=fatal") {
                NSLog("mpv: %@", line)
            }
            #endif
        }
    }

    private func bindControls() {
        controlsView.onClose = { [weak self] in
            self?.closePlayer()
        }

        controlsView.onOpen = { [weak self] in
            self?.closePlayer()
        }

        controlsView.onOpenFolder = { [weak self] in
            self?.closePlayer()
        }

        controlsView.onOpenSubtitle = { [weak self] in
            self?.presentSubtitleDocumentPicker()
        }

        controlsView.onSubtitlePositionChanged = { [weak self] position in
            self?.setSubtitlePosition(position)
        }

        controlsView.onSubtitleScaleChanged = { [weak self] scale in
            self?.setSubtitleScale(scale)
        }

        controlsView.onSubtitleBorderSizeChanged = { [weak self] borderSize in
            self?.setSubtitleBorderSize(borderSize)
        }

        controlsView.onSubtitleDelayChanged = { [weak self] delay in
            self?.setSubtitleDelay(delay)
        }

        controlsView.onSubtitleAdjustmentVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.controlsHidden = true
            self.setNeedsStatusBarAppearanceUpdate()
            if visible {
                self.cancelControlsHide()
                self.hideSeekPreviewNow()
                self.hideGestureHUDNow()
                self.updateRenderedSubtitlePosition(controlsHidden: true, animated: true)
            } else {
                self.cancelControlsHide()
                self.updateRenderedSubtitlePosition(controlsHidden: true, animated: true)
            }
        }

        controlsView.onSubtitleAdjustmentEnded = { [weak self] in
            self?.persistSubtitleAdjustmentSettingsNow()
        }

        controlsView.onDisableSubtitle = { [weak self] in
            guard let self else { return }
            self.player.disableSubtitle()
            self.updateRenderedSubtitle(nil)
            self.scheduleControlsHide()
        }

        controlsView.onPlayPause = { [weak self] in
            guard let self else { return }
            self.attachPlayerIfNeeded()
            self.manager?.togglePlayPause()
            self.scheduleControlsHide()
        }

        controlsView.onPreviousEpisode = { [weak self] in
            self?.playAdjacentItem(offset: -1)
        }

        controlsView.onSeekBegan = { [weak self] in
            self?.cancelControlsHide()
            self?.hideSeekPreviewNow()
        }

        controlsView.onSeekChanged = { [weak self] seconds in
            guard let self else { return }
            self.controlsView.update(time: seconds, duration: max(self.player.duration, seconds))
        }

        controlsView.onSeekEnded = { [weak self] seconds in
            self?.player.seek(to: seconds)
            self?.scheduleControlsHide(after: 1.0)
        }

        controlsView.onSeekBackward = { [weak self] in
            self?.jumpBackward(Defaults[.VideoPlayer.jumpBackwardInterval].rawValue)
            self?.scheduleControlsHide()
        }

        controlsView.onSeekForward = { [weak self] in
            self?.jumpForward(Defaults[.VideoPlayer.jumpForwardInterval].rawValue)
            self?.scheduleControlsHide()
        }

        controlsView.onSkipIntro = { [weak self] seconds in
            guard let self else { return }
            SkipIntroDismissalStore.setDismissed(true, item: self.manager?.item)
            if seconds >= 0 {
                self.jumpForward(.seconds(seconds))
            } else {
                self.jumpBackward(.seconds(abs(seconds)))
            }
            self.scheduleControlsHide()
        }

        controlsView.onSkipIntroAdjustmentBegan = { [weak self] in
            guard let self else { return }
            self.pause()
            self.controlsView.setPaused(true, showsIndicator: false)
        }

        controlsView.onSkipIntroAdjustmentCommitted = { [weak self] seconds in
            guard let self else { return }
            SkipIntroDismissalStore.setSeconds(seconds, for: self.manager?.item)
            SkipIntroDismissalStore.setDismissed(true, item: self.manager?.item)
            self.scheduleControlsHide(after: 0)
        }

        controlsView.onSkipIntroAdjustmentEnded = { [weak self] in
            guard let self else { return }
            self.play()
            self.controlsView.setPaused(false)
        }

        controlsView.onNextEpisode = { [weak self] in
            self?.playAdjacentItem(offset: 1)
        }

        controlsView.onEpisodeList = { [weak self] in
            self?.toggleEpisodeList()
        }

        controlsView.onPlaybackSpeedSelected = { [weak self] speed in
            guard let self else { return }
            let rate = Float(speed)
            self.manager?.setRate(rate: rate)
            self.setRate(rate)
            self.scheduleControlsHide()
        }

        controlsView.onMenuOpened = { [weak self] in
            guard let self else { return }
            self.cancelControlsHide()
            self.scheduleControlsHide(after: 5.0)
        }

        controlsView.onMenuSelectionFinished = { [weak self] in
            self?.scheduleControlsHide()
        }

        controlsView.onSelectSubtitleTrack = { [weak self] id in
            guard let self else { return }
            self.player.selectSubtitleTrack(id: id)
            self.reapplySubtitleAdjustmentSettings(reason: "manual-subtitle-select")
            self.scheduleSubtitleAdjustmentReapply(reason: "manual-subtitle-select-delayed", after: 0.18)
            self.scheduleControlsHide()
        }
    }

    private func installGestures() {
        let gestures = PlayerGestureController(view: controlsView)
        gestures.onToggleControls = { [weak self] in
            self?.toggleControls()
        }
        gestures.onTogglePlayback = { [weak self] in
            guard let self else { return }
            guard !self.controlsView.isSubtitleAdjustmentPanelVisible else { return }
            self.attachPlayerIfNeeded()
            self.manager?.togglePlayPause()
        }
        gestures.onSeekBy = { [weak self] seconds in
            self?.player.seek(by: seconds)
            self?.scheduleControlsHide()
        }
        gestures.onSeekGestureChanged = { [weak self] seconds, state in
            self?.handleSeekGesture(delta: seconds, state: state)
        }
        gestures.onLongPressSpeedChanged = { [weak self] state in
            self?.handleLongPressSpeedGesture(state: state)
        }
        gestures.onVerticalAdjustmentChanged = { [weak self] side, delta, state in
            self?.handleVerticalAdjustment(side: side, delta: delta, state: state)
        }
        gestureController = gestures
    }

    @discardableResult
    private func attachPlayerIfNeeded() -> Bool {
        do {
            try player.attach(to: playerView)
            applySubtitleAdjustmentSettings()
            return true
        } catch {
            presentError(error.localizedDescription)
            manager?.error(ErrorMessage("libmpv failed to initialize: \(error.localizedDescription)"))
            return false
        }
    }

    private func playNew(item: MediaPlayerItem) {
        hidePlaybackChromeForNewItem()
        loadSubtitleAdjustmentSettings(for: item.baseItem)
        prepareVideoSurfaceForLoading()
        guard attachPlayerIfNeeded() else { return }

        didStopPlayback = false
        didShutdownForDismissal = false
        UIApplication.shared.isIdleTimerDisabled = true
        isBuffering.value = true
        controlsView.update(time: item.baseItem.startSeconds?.seconds ?? 0, duration: item.baseItem.runtime?.seconds ?? 0)
        updateEpisodeNavigation()
        updateEpisodeListForCurrentItemIfNeeded(item.baseItem)

        let startSeconds: Duration
        if !item.baseItem.isLiveStream {
            startSeconds = max(.zero, (item.baseItem.startSeconds ?? .zero) - Duration.seconds(Defaults[.VideoPlayer.resumeOffset]))
        } else {
            startSeconds = .zero
        }

        currentSubtitleIdentifiers.removeAll()
        pendingDefaultExternalSubtitleTitle = nil
        pendingDefaultExternalSubtitleClearGeneration += 1
        convertedEmbeddedSubtitleTitlesByOriginalIndex.removeAll()
        updateRenderedSubtitle(nil)

        applyDefaultTrackLanguageOptions()
        player.load(url: item.url, headers: item.httpHeaders, startSeconds: startSeconds.seconds)
        activatePlaybackAudioSession(reason: "playNew")
        applySubtitleAdjustmentSettings()
        setRate(manager?.rate ?? 1)
        let addedEmbeddedConvertedSubtitleCount = addEmbeddedConvertedSubtitles(for: item)
        let addedExternalSubtitleURLs = addExternalSubtitles(for: item)
        let addedExternalSubtitleCount = addedExternalSubtitleURLs.count
        let addedLocalSubtitleCount = addLocalSubtitles(for: item.url)
        let addedSubtitleCount = addedEmbeddedConvertedSubtitleCount + addedExternalSubtitleCount + addedLocalSubtitleCount

        #if DEBUG
        NSLog("EmbyPlayerResume item=%@ startSeconds=%.3f", item.baseItem.id ?? "<nil>", startSeconds.seconds)
        pendingResumeObservation = (item.baseItem.id ?? "<nil>", startSeconds.seconds)
        #endif

        if let audio = defaultAudioStream(for: item) {
            setAudioStream(audio)
        }

        if let subtitle = defaultSubtitleStream(for: item) {
            applyDefaultSubtitleStream(subtitle, addedSubtitleCount: addedSubtitleCount, reason: "language")
        } else if item.mediaSource.defaultSubtitleStreamIndex == -1 {
            player.disableSubtitle()
            updateRenderedSubtitle(nil)
            #if DEBUG
            NSLog("EmbyPlayerSubtitleSetup default=off")
            #endif
        } else if let defaultSubtitleStreamIndex = item.mediaSource.defaultSubtitleStreamIndex,
                  let subtitle = item.subtitleStreams.first(where: { subtitleStream($0, matchesOriginalOrAdjustedIndex: defaultSubtitleStreamIndex) }) {
            applyDefaultSubtitleStream(subtitle, addedSubtitleCount: addedSubtitleCount, reason: "server")
        } else if addedSubtitleCount > 0 {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleSetup default=auto added=%d", addedSubtitleCount)
            #endif
        } else {
            player.disableSubtitle()
            updateRenderedSubtitle(nil)
            #if DEBUG
            NSLog("EmbyPlayerSubtitleSetup default=none added=0")
            #endif
        }
    }

    private func applyDefaultTrackLanguageOptions() {
        let audio = Defaults[.VideoPlayer.Playback.defaultAudioLanguage]
        let subtitle = Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage]
        let mpvAudioLanguages = audio.mpvLanguageList ??
            (audio == .automatic ? MediaTrackLanguagePreference.automaticAudioMPVLanguageList : nil)
        let mpvSubtitleLanguages = subtitle.mpvLanguageList ??
            (subtitle == .automatic ? MediaTrackLanguagePreference.automaticSubtitleMPVLanguageList : nil)

        player.setPreferredAudioLanguages(mpvAudioLanguages)
        player.setPreferredSubtitleLanguages(mpvSubtitleLanguages)

        #if DEBUG
        NSLog(
            "EmbyPlayerDefaultTrackLanguages audio=%@ subtitle=%@ mpvAudio=%@ mpvSubtitle=%@",
            audio.displayTitle,
            subtitle.displayTitle,
            mpvAudioLanguages ?? "<auto>",
            mpvSubtitleLanguages ?? "<auto>"
        )
        #endif
    }

    private func defaultAudioStream(for item: MediaPlayerItem) -> MediaStream? {
        let preference = Defaults[.VideoPlayer.Playback.defaultAudioLanguage]
        if let stream = preference.preferredStream(in: item.audioStreams) {
            #if DEBUG
            NSLog("EmbyPlayerAudioSetup default=language language=%@ index=%d title=%@",
                  preference.displayTitle,
                  stream.index ?? -1,
                  stream.displayTitle ?? stream.title ?? stream.language ?? "<nil>")
            #endif
            return stream
        }

        if preference == .automatic,
           let stream = MediaTrackLanguagePreference.automaticAudioStream(in: item.audioStreams) {
            #if DEBUG
            NSLog("EmbyPlayerAudioSetup default=auto language=%@ index=%d title=%@",
                  stream.language ?? "<nil>",
                  stream.index ?? -1,
                  stream.displayTitle ?? stream.title ?? stream.language ?? "<nil>")
            #endif
            return stream
        }

        return item.audioStreams.first { $0.index == item.mediaSource.defaultAudioStreamIndex }
    }

    private func defaultSubtitleStream(for item: MediaPlayerItem) -> MediaStream? {
        let preference = Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage]
        guard let stream = preference.preferredStream(in: item.subtitleStreams) ??
            (preference == .automatic ? MediaTrackLanguagePreference.automaticSubtitleStream(in: item.subtitleStreams) : nil) ??
            item.subtitleStreams.first else {
            return nil
        }

        #if DEBUG
        NSLog("EmbyPlayerSubtitleSetup default=language language=%@ index=%d title=%@",
              preference == .automatic ? "自动" : preference.displayTitle,
              stream.index ?? -1,
              stream.displayTitle ?? stream.title ?? stream.language ?? "<nil>")
        #endif
        return stream
    }

    private func applyDefaultSubtitleStream(_ subtitle: MediaStream, addedSubtitleCount: Int, reason: String) {
        if isExternalSubtitle(subtitle),
           let url = externalSubtitleURL(for: subtitle) {
            player.disableSubtitle()
            updateRenderedSubtitle(nil)
            pendingDefaultExternalSubtitleTitle = externalSubtitleTitle(for: subtitle, url: url)
            #if DEBUG
            NSLog(
                "EmbyPlayerSubtitleSetup default=%@-external pendingTitle=%@ added=%d",
                reason,
                pendingDefaultExternalSubtitleTitle ?? url.lastPathComponent,
                addedSubtitleCount
            )
            #endif
        } else {
            if let originalIndex = subtitleOriginalIndex(subtitle),
               let convertedTitle = convertedEmbeddedSubtitleTitlesByOriginalIndex[originalIndex] {
                player.disableSubtitle()
                updateRenderedSubtitle(nil)
                pendingDefaultExternalSubtitleTitle = convertedTitle
                #if DEBUG
                NSLog(
                    "EmbyPlayerSubtitleSetup default=%@-embedded-converted pendingTitle=%@ sourceIndex=%d added=%d",
                    reason,
                    convertedTitle,
                    originalIndex,
                    addedSubtitleCount
                )
                #endif
                return
            }
            setSubtitleStream(subtitle)
            #if DEBUG
            NSLog("EmbyPlayerSubtitleSetup default=%@-embedded index=%d", reason, subtitle.index ?? -1)
            #endif
        }
    }

    private func pendingDefaultSubtitleTrack(in tracks: [MPVSubtitleTrack], title: String) -> MPVSubtitleTrack? {
        tracks.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame } ??
            tracks.first {
                $0.title.localizedCaseInsensitiveContains(title) ||
                    title.localizedCaseInsensitiveContains($0.title)
            }
    }

    private func schedulePendingDefaultExternalSubtitleClear(title: String) {
        pendingDefaultExternalSubtitleClearGeneration += 1
        let generation = pendingDefaultExternalSubtitleClearGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self,
                  self.pendingDefaultExternalSubtitleClearGeneration == generation,
                  self.pendingDefaultExternalSubtitleTitle == title
            else { return }

            self.pendingDefaultExternalSubtitleTitle = nil
        }
    }

    @discardableResult
    private func addEmbeddedConvertedSubtitles(for item: MediaPlayerItem) -> Int {
        let shouldConvert = Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles]
        let client = Container.shared.currentUserSession()?.embyClient
        let itemID = item.baseItem.id
        let mediaSourceID = item.mediaSource.id

        #if DEBUG
        NSLog(
            "EmbyPlayerEmbeddedConvertedSubtitles enter enabled=%@ item=%@ mediaSource=%@ subtitles=%d",
            shouldConvert.description,
            itemID ?? "<nil>",
            mediaSourceID ?? "<nil>",
            item.subtitleStreams.count
        )
        #endif

        guard shouldConvert,
              let client,
              let itemID,
              let mediaSourceID
        else {
            #if DEBUG
            NSLog(
                "EmbyPlayerEmbeddedConvertedSubtitles skipped enabled=%@ hasClient=%@ item=%@ mediaSource=%@",
                shouldConvert.description,
                (client != nil).description,
                itemID ?? "<nil>",
                mediaSourceID ?? "<nil>"
            )
            #endif
            return 0
        }

        var candidateCount = 0
        var addedCount = 0
        for stream in item.subtitleStreams where !isExternalSubtitle(stream) {
            candidateCount += 1
            guard shouldConvertStreamSubtitle(stream) else {
                #if DEBUG
                NSLog("EmbyPlayerEmbeddedSubtitleSkip reason=non-chinese index=%d title=%@ language=%@",
                      stream.index ?? -1,
                      stream.displayTitle ?? stream.title ?? "<nil>",
                      stream.language ?? "<nil>")
                #endif
                continue
            }

            guard let originalIndex = subtitleOriginalIndex(stream) else {
                #if DEBUG
                NSLog("EmbyPlayerEmbeddedSubtitleSkip reason=missing-index title=%@", stream.displayTitle ?? stream.title ?? "<nil>")
                #endif
                continue
            }

            let urls = embeddedSubtitleStreamURLs(itemID: itemID,
                                                  mediaSourceID: mediaSourceID,
                                                  streamIndex: originalIndex,
                                                  stream: stream,
                                                  client: client)
            guard let url = urls.first,
                  MPVSubtitleFileConverter.canConvert(url: url,
                                                      codec: stream.codec,
                                                      isTextSubtitle: stream.isTextSubtitleStream)
            else {
                #if DEBUG
                NSLog("EmbyPlayerEmbeddedSubtitleSkip reason=not-text index=%d codec=%@ text=%@",
                      originalIndex,
                      stream.codec ?? "<nil>",
                      stream.isTextSubtitleStream.map(\.description) ?? "<nil>")
                #endif
                continue
            }

            let title = convertedEmbeddedSubtitleTitle(for: stream, originalIndex: originalIndex)
            let identifier = "emby-embedded-converted://\(itemID)/\(mediaSourceID)/\(originalIndex)"
            if addSubtitleIfNeeded(url: url,
                                   fallbackURLs: Array(urls.dropFirst()),
                                   title: title,
                                   reason: "emby-embedded-converted",
                                   identifier: identifier,
                                   headers: client.playbackHeaders,
                                   stream: stream,
                                   fallbackToOriginal: false) {
                convertedEmbeddedSubtitleTitlesByOriginalIndex[originalIndex] = title
                addedCount += 1
            }
        }

        #if DEBUG
        NSLog(
            "EmbyPlayerEmbeddedConvertedSubtitles candidates=%d added=%d",
            candidateCount,
            addedCount
        )
        #endif

        return addedCount
    }

    @discardableResult
    private func addExternalSubtitles(for item: MediaPlayerItem) -> [(url: URL, title: String)] {
        guard let client = Container.shared.currentUserSession()?.embyClient else { return [] }

        var candidateCount = 0
        var addedSubtitles: [(url: URL, title: String)] = []
        for stream in item.subtitleStreams where isExternalSubtitle(stream) {
            candidateCount += 1
            guard let url = externalSubtitleURL(for: stream, client: client) else {
                #if DEBUG
                NSLog("EmbyPlayerExternalSubtitleSkip reason=missing-url index=%d title=%@", stream.index ?? -1, stream.displayTitle ?? stream.title ?? "<nil>")
                #endif
                continue
            }

            let title = externalSubtitleTitle(for: stream, url: url)
            if addSubtitleIfNeeded(url: url,
                                   title: title,
                                   reason: "emby-external",
                                   headers: client.playbackHeaders,
                                   stream: stream) {
                addedSubtitles.append((url, title))
            }
        }

        #if DEBUG
        NSLog(
            "EmbyPlayerExternalSubtitles candidates=%d added=%d",
            candidateCount,
            addedSubtitles.count
        )
        #endif

        return addedSubtitles
    }

    @discardableResult
    private func addLocalSubtitles(for mediaURL: URL) -> Int {
        guard mediaURL.isFileURL else { return 0 }

        do {
            let urls = try MPVSubtitleAutoLoader.matchingSubtitleURLs(for: mediaURL)
            #if DEBUG
            NSLog("EmbyPlayerLocalSubtitleScan media=%@ count=%d", mediaURL.lastPathComponent, urls.count)
            #endif

            return urls.reduce(0) { count, url in
                count + (addSubtitleIfNeeded(url: url, title: nil, reason: "local-sidecar") ? 1 : 0)
            }
        } catch {
            #if DEBUG
            NSLog("EmbyPlayerLocalSubtitleScan media=%@ error=%@", mediaURL.lastPathComponent, error.localizedDescription)
            #endif
            return 0
        }
    }

    @discardableResult
    private func addSubtitleIfNeeded(url: URL,
                                     fallbackURLs: [URL] = [],
                                     title: String?,
                                     reason: String,
                                     identifier explicitIdentifier: String? = nil,
                                     headers: [String: String] = [:],
                                     stream: MediaStream? = nil,
                                     fallbackToOriginal: Bool = true) -> Bool {
        let identifier = explicitIdentifier ?? MPVSubtitleAutoLoader.normalizedIdentifier(for: url)
        guard currentSubtitleIdentifiers.insert(identifier).inserted else {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleAdd reason=%@ result=duplicate path=%@", reason, identifier)
            #endif
            return false
        }

        let shouldConvert = shouldConvertSubtitle(url: url, stream: stream)

        #if DEBUG
        NSLog("EmbyPlayerSubtitleAdd reason=%@ path=%@ title=%@ convertTraditionalChinese=%@",
              reason,
              identifier,
              title ?? "<nil>",
              shouldConvert.description)
        #endif
        player.addSubtitle(url: url,
                           fallbackURLs: fallbackURLs,
                           title: title,
                           headers: headers,
                           convertTraditionalChinese: shouldConvert,
                           sourceCodec: stream?.codec,
                           isTextSubtitle: stream?.isTextSubtitleStream,
                           fallbackToOriginal: fallbackToOriginal)
        return true
    }

    private func isExternalSubtitle(_ stream: MediaStream) -> Bool {
        stream.deliveryMethod == .external ||
            stream.isExternal == true ||
            stream.deliveryURL?.isEmpty == false
    }

    private func shouldConvertSubtitle(url: URL, stream: MediaStream?) -> Bool {
        guard Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles],
              MPVSubtitleFileConverter.canConvert(url: url,
                                                  codec: stream?.codec,
                                                  isTextSubtitle: stream?.isTextSubtitleStream)
        else {
            return false
        }

        guard let stream else {
            return true
        }

        return shouldConvertStreamSubtitle(stream)
    }

    private func shouldConvertStreamSubtitle(_ stream: MediaStream) -> Bool {
        MediaTrackLanguagePreference.chinese.matches(stream) ||
            MediaTrackLanguagePreference.cantonese.matches(stream)
    }

    private func externalSubtitleURL(for stream: MediaStream) -> URL? {
        guard let client = Container.shared.currentUserSession()?.embyClient else { return nil }
        return externalSubtitleURL(for: stream, client: client)
    }

    private func externalSubtitleURL(for stream: MediaStream, client: EmbyPortSessionClient) -> URL? {
        guard let deliveryURL = stream.deliveryURL, !deliveryURL.isEmpty else { return nil }
        return client.absoluteURL(forPathOrURL: deliveryURL)
    }

    private func embeddedSubtitleStreamURLs(itemID: String,
                                            mediaSourceID: String,
                                            streamIndex: Int,
                                            stream: MediaStream,
                                            client: EmbyPortSessionClient) -> [URL] {
        var seen = Set<String>()
        return embeddedSubtitleExtractionFormats(for: stream).flatMap { format in
            client.subtitleStreamURLs(itemID: itemID,
                                      mediaSourceID: mediaSourceID,
                                      streamIndex: streamIndex,
                                      format: format)
        }.compactMap { url in
            seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    private func embeddedSubtitleExtractionFormats(for stream: MediaStream) -> [String] {
        let codec = normalizedSubtitleCodec(stream.codec)
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

    private func convertedEmbeddedSubtitleTitle(for stream: MediaStream, originalIndex: Int) -> String {
        let primary = [
            stream.displayTitle,
            stream.title,
        ]
            .compactMap { sanitizedExternalSubtitleTitle($0) }
            .first

        var parts: [String] = []
        if let primary {
            parts.append(primary)
        } else {
            parts.append("内封字幕 \(originalIndex)")
        }

        if let language = stream.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(language) }) {
            parts.append(language.uppercased())
        }

        if let codec = stream.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(codec) }) {
            parts.append(codec.uppercased())
        }

        if shouldConvertStreamSubtitle(stream) {
            parts.append("简体")
        }
        return parts.joined(separator: " · ")
    }

    private func normalizedSubtitleCodec(_ codec: String?) -> String {
        codec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() ?? ""
    }

    private func subtitleOriginalIndex(_ stream: MediaStream) -> Int? {
        stream.originalIndex ?? stream.index
    }

    private func subtitleStream(_ stream: MediaStream, matchesOriginalOrAdjustedIndex index: Int) -> Bool {
        stream.index == index || stream.originalIndex == index
    }

    private func externalSubtitleTitle(for stream: MediaStream, url: URL) -> String {
        let primary = [
            stream.displayTitle,
            stream.title,
        ]
            .compactMap { sanitizedExternalSubtitleTitle($0) }
            .first

        var parts: [String] = []
        if let primary {
            parts.append(primary)
        }

        if let language = stream.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            let uppercased = language.uppercased()
            if !parts.contains(where: { $0.localizedCaseInsensitiveContains(language) }) {
                parts.append(uppercased)
            }
        }

        if let codec = stream.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty {
            let uppercased = codec.uppercased()
            if !parts.contains(where: { $0.localizedCaseInsensitiveContains(codec) }) {
                parts.append(uppercased)
            }
        }

        if stream.isForced == true {
            parts.append("强制")
        }

        if parts.isEmpty {
            let fallback = url.deletingPathExtension().lastPathComponent
            parts.append(fallback.isEmpty || fallback == "Stream" ? "外部字幕" : fallback)
        }

        return parts.joined(separator: " · ")
    }

    private func sanitizedExternalSubtitleTitle(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let stem = (trimmed as NSString).deletingPathExtension
        let genericNames: Set<String> = [
            "stream",
            "subtitle",
            "subtitles",
            "external",
            "external subtitle",
        ]
        if genericNames.contains(trimmed.lowercased()) || genericNames.contains(stem.lowercased()) {
            return nil
        }

        return trimmed
    }

    private func playAdjacentItem(offset: Int) {
        let provider = offset < 0 ? manager?.queue?.previousItem : manager?.queue?.nextItem
        guard let provider else {
            showControls()
            return
        }

        controlsView.suppressPausedIndicatorTemporarily()
        manager?.playNewItem(provider: provider)
        hidePlaybackChromeForNewItem()
    }

    private func toggleEpisodeList() {
        guard manager?.queue != nil else {
            showControls()
            return
        }

        setEpisodeListVisible(!isEpisodeListVisible, animated: true)
    }

    private func setEpisodeListVisible(_ visible: Bool, animated: Bool) {
        guard isEpisodeListVisible != visible else {
            if visible {
                loadEpisodeListIfNeeded()
            }
            return
        }

        isEpisodeListVisible = visible
        if visible {
            cancelControlsHide()
            hideSeekPreviewNow()
            hideGestureHUDNow()
            showControls()
            cancelControlsHide()
            episodeListPanel.isHidden = false
            episodeListPanel.isUserInteractionEnabled = true
            loadEpisodeListIfNeeded()
        } else {
            episodeListPanel.isUserInteractionEnabled = false
        }

        let animations = {
            self.episodeListPanel.alpha = visible ? 1 : 0
            self.episodeListPanel.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 14)
        }

        if animated {
            UIView.animate(
                withDuration: visible ? 0.18 : 0.14,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: animations
            ) { [weak self] _ in
                guard let self else { return }
                self.episodeListPanel.isHidden = !self.isEpisodeListVisible
            }
        } else {
            animations()
            episodeListPanel.isHidden = !visible
        }

        if !visible {
            scheduleControlsHide()
        }
    }

    private func closeEpisodeListForPlayerDismissal() {
        episodeListLoadTask?.cancel()
        episodeListLoadTask = nil
        isEpisodeListVisible = false
        episodeListPanel.layer.removeAllAnimations()
        episodeListPanel.alpha = 0
        episodeListPanel.transform = CGAffineTransform(translationX: 0, y: 14)
        episodeListPanel.isHidden = true
        episodeListPanel.isUserInteractionEnabled = false
        episodeListLoadingIndicator.stopAnimating()
    }

    private func loadEpisodeListIfNeeded() {
        guard let item = manager?.item,
              let seriesID = item.seriesID ?? item.parentID
        else { return }

        if episodeListSeriesID == seriesID, !episodeListItems.isEmpty {
            episodeListTableView.reloadData()
            scrollEpisodeListToCurrentItem(animated: false)
            return
        }

        episodeListSeriesID = seriesID
        episodeListItems = []
        episodeListTableView.reloadData()
        episodeListLoadingIndicator.startAnimating()
        episodeListLoadTask?.cancel()
        episodeListLoadTask = Task { [weak self] in
            guard let self else { return }
            guard let userSession = Container.shared.currentUserSession() else {
                await MainActor.run {
                    self.episodeListLoadingIndicator.stopAnimating()
                }
                return
            }

            var parameters = EmbyPortEpisodesParameters()
            parameters.enableUserData = true
            parameters.fields = .MinimumFields
            parameters.isMissing = false
            parameters.userID = userSession.user.id

            do {
                let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.episodes(
                    seriesID: seriesID,
                    parameters,
                    as: EmbyPortItemsResponse<BaseItemDto>.self
                )

                await MainActor.run {
                    guard !Task.isCancelled, self.episodeListSeriesID == seriesID else { return }
                    self.episodeListItems = response.items ?? []
                    self.episodeListLoadingIndicator.stopAnimating()
                    self.episodeListTableView.reloadData()
                    self.scrollEpisodeListToCurrentItem(animated: false)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.episodeListItems = []
                    self.episodeListLoadingIndicator.stopAnimating()
                    self.episodeListTableView.reloadData()
                    #if DEBUG
                    NSLog("EmbyPlayerEpisodeList load failed error=%@", error.localizedDescription)
                    #endif
                }
            }
        }
    }

    private func scrollEpisodeListToCurrentItem(animated: Bool) {
        guard let currentID = manager?.item.id,
              let row = episodeListItems.firstIndex(where: { $0.id == currentID })
        else { return }

        episodeListTableView.scrollToRow(
            at: IndexPath(row: row, section: 0),
            at: .middle,
            animated: animated
        )
    }

    private func updateEpisodeListForCurrentItemIfNeeded(_ item: BaseItemDto) {
        guard isEpisodeListVisible else { return }
        let seriesID = item.seriesID ?? item.parentID
        if seriesID != episodeListSeriesID {
            episodeListSeriesID = nil
            loadEpisodeListIfNeeded()
        } else {
            episodeListTableView.reloadData()
            scrollEpisodeListToCurrentItem(animated: true)
        }
    }

    private func selectEpisodeListItem(at indexPath: IndexPath) {
        guard episodeListItems.indices.contains(indexPath.row) else { return }
        let episode = episodeListItems[indexPath.row]
        if episode.id == manager?.item.id {
            setEpisodeListVisible(false, animated: true)
            return
        }

        controlsView.suppressPausedIndicatorTemporarily()
        let provider = MediaPlayerItemProvider(item: episode) { item in
            try await MediaPlayerItem.build(for: item)
        }
        manager?.playNewItem(provider: provider)
        setEpisodeListVisible(false, animated: true)
        hidePlaybackChromeForNewItem()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard tableView === episodeListTableView else { return 0 }
        return episodeListItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.episodeListCellIdentifier, for: indexPath)
        guard episodeListItems.indices.contains(indexPath.row) else { return cell }

        let episode = episodeListItems[indexPath.row]
        var content = cell.defaultContentConfiguration()
        if let locator = episode.seasonEpisodeLabel {
            content.text = "\(locator) · \(episode.displayTitle)"
        } else {
            content.text = episode.displayTitle
        }
        content.textProperties.color = .white
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)

        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.tintColor = .white
        cell.accessoryType = episode.id == manager?.item.id ? .checkmark : .none
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectedBackground

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard tableView === episodeListTableView else { return }
        selectEpisodeListItem(at: indexPath)
    }

    private func presentSubtitleDocumentPicker() {
        cancelControlsHide()
        showControls()
        shouldResumeAfterSubtitlePicker = !player.isPaused
        if shouldResumeAfterSubtitlePicker {
            controlsView.suppressPausedIndicatorTemporarily()
            player.setPaused(true)
        }

        let subtitleTypes = Self.subtitleDocumentTypes
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: subtitleTypes, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    private static var subtitleDocumentTypes: [UTType] {
        let extensions = [
            "ass",
            "srt",
            "ssa",
            "sub",
            "vtt",
            "webvtt",
        ]
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.plainText] : types + [.plainText]
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self, let url = urls.first else { return }
            let shouldResume = self.shouldResumeAfterSubtitlePicker
            self.shouldResumeAfterSubtitlePicker = false
            let title = url.deletingPathExtension().lastPathComponent
            self.pendingDefaultExternalSubtitleTitle = title
            _ = self.addSubtitleIfNeeded(
                url: url,
                title: title,
                reason: "user-selected"
            )
            if shouldResume {
                self.player.setPaused(false)
            }
            self.showControls()
            self.scheduleControlsHide()
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let shouldResume = self.shouldResumeAfterSubtitlePicker
            self.shouldResumeAfterSubtitlePicker = false
            if shouldResume {
                self.player.setPaused(false)
            }
            self.scheduleControlsHide()
        }
    }

    private func updateEpisodeNavigation() {
        let hasQueue = manager?.queue != nil
        if !hasQueue, isEpisodeListVisible {
            setEpisodeListVisible(false, animated: true)
        }

        controlsView.updateEpisodeNavigation(
            canGoPrevious: manager?.queue?.previousItem != nil,
            canGoNext: manager?.queue?.nextItem != nil,
            canShowEpisodeList: hasQueue
        )
    }

    private func toggleControls() {
        if controlsView.isSubtitleAdjustmentPanelVisible {
            controlsView.setSubtitleAdjustmentPanelVisible(false, animated: true)
            return
        }

        if isEpisodeListVisible {
            setEpisodeListVisible(false, animated: true)
            return
        }

        controlsHidden ? showControls() : hideControls()
    }

    private func showControls() {
        if controlsView.isSubtitleAdjustmentPanelVisible {
            return
        }

        controlsHidden = false
        setNeedsStatusBarAppearanceUpdate()
        controlsView.setControlsHidden(false, animated: true)
        updateRenderedSubtitlePosition(controlsHidden: false, animated: true)
        scheduleControlsHide()
    }

    private func hideControls(animated: Bool = true) {
        if controlsView.isSubtitleAdjustmentPanelVisible {
            return
        }
        if controlsView.isSkipIntroAdjustmentActive {
            return
        }

        controlsHidden = true
        setNeedsStatusBarAppearanceUpdate()
        cancelControlsHide()
        controlsView.setControlsHidden(true, animated: animated)
        updateRenderedSubtitlePosition(controlsHidden: true, animated: animated)
    }

    private func hidePlaybackChromeForNewItem() {
        controlsView.suppressPausedIndicatorTemporarily()
        hideSeekPreviewNow()
        hideGestureHUDNow()
        if isEpisodeListVisible {
            setEpisodeListVisible(false, animated: false)
        }
        hideControls(animated: false)
    }

    private func updateRenderedSubtitle(_ text: String?) {
        let displayText = normalizedSubtitleOverlayText(text)
        guard let displayText else {
            hideRenderedSubtitle()
            #if DEBUG
            NSLog("EmbyPlayerRenderedSubtitle visible=false")
            #endif
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let strokeWidth = subtitleBorderSize > 0 ? -(subtitleBorderSize / 3.0) * 3.8 : 0

        renderedSubtitleLabel.attributedText = NSAttributedString(
            string: displayText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 29 * CGFloat(subtitleScale), weight: .semibold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: strokeWidth,
                .paragraphStyle: paragraphStyle,
            ]
        )
        view.bringSubviewToFront(renderedSubtitleLabel)
        UIView.animate(withDuration: 0.08) {
            self.renderedSubtitleLabel.alpha = 1
        }

        #if DEBUG
        view.layoutIfNeeded()
        NSLog(
            "EmbyPlayerRenderedSubtitle visible=true text=%@ frame=%@",
            displayText.replacingOccurrences(of: "\n", with: "\\n"),
            "\(renderedSubtitleLabel.frame)"
        )
        #endif
    }

    private func hideRenderedSubtitle() {
        UIView.animate(withDuration: 0.12) {
            self.renderedSubtitleLabel.alpha = 0
        }
    }

    private func normalizedSubtitleOverlayText(_ text: String?) -> String? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        value = value
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")

        while let range = value.range(of: #"\{[^}]*\}"#, options: .regularExpression) {
            value.removeSubrange(range)
        }

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let dialogueLines = lines.filter { !isSubtitleOverlayNoiseLine($0) }
        let selectedLines: [String]
        if !dialogueLines.isEmpty {
            selectedLines = Array(dialogueLines.suffix(2))
        } else if lines.count > 1 {
            selectedLines = Array(lines.filter { $0.count <= 42 }.suffix(2))
        } else if let onlyLine = lines.first, onlyLine.count <= 80 {
            selectedLines = [onlyLine]
        } else {
            selectedLines = []
        }

        value = selectedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isSubtitleOverlayNoiseLine(_ line: String) -> Bool {
        guard line.count > 42 else { return false }

        let lowercased = line.lowercased()
        let markers = [
            "dmzj",
            "bbs.",
            "字幕组",
            "仅供",
            "试看",
            "商业用途",
            "下载后",
            "24小时",
            "购买正版",
            "违法",
        ]
        return markers.contains { lowercased.contains($0) }
    }

    private func updateRenderedSubtitlePosition(controlsHidden: Bool, animated: Bool) {
        subtitleControlsBottomConstraint?.isActive = !controlsHidden
        subtitleVisibleBottomConstraint?.isActive = controlsHidden

        let changes = {
            self.view.layoutIfNeeded()
            self.updateRenderedSubtitleTransform()
        }

        if animated {
            UIView.animate(withDuration: 0.18, animations: changes)
        } else {
            changes()
        }
    }

    private func setSubtitlePosition(_ position: Double) {
        let clampedPosition = Self.clampedSubtitlePosition(position)
        guard subtitlePosition != clampedPosition else { return }
        subtitlePosition = clampedPosition
        subtitleAdjustmentSettingsDidChange = true
        player.setSubtitlePosition(subtitlePosition)
        updateRenderedSubtitleTransform()
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        scheduleSubtitleAdjustmentPersistence()
        logSubtitleAdjustmentIfNeeded()
    }

    private func setSubtitleScale(_ scale: Double) {
        let clampedScale = Self.clampedSubtitleScale(scale)
        guard subtitleScale != clampedScale else { return }
        subtitleScale = clampedScale
        subtitleAdjustmentSettingsDidChange = true
        player.setSubtitleScale(subtitleScale)
        if renderedSubtitleLabel.alpha > 0 {
            updateRenderedSubtitle(renderedSubtitleLabel.attributedText?.string)
        }
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        scheduleSubtitleAdjustmentPersistence()
        logSubtitleAdjustmentIfNeeded()
    }

    private func setSubtitleBorderSize(_ borderSize: Double) {
        let clampedBorderSize = Self.clampedSubtitleBorderSize(borderSize)
        guard subtitleBorderSize != clampedBorderSize else { return }
        subtitleBorderSize = clampedBorderSize
        subtitleAdjustmentSettingsDidChange = true
        player.setSubtitleBorderSize(subtitleBorderSize)
        updateRenderedSubtitleOutline()
        if renderedSubtitleLabel.alpha > 0 {
            updateRenderedSubtitle(renderedSubtitleLabel.attributedText?.string)
        }
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        scheduleSubtitleAdjustmentPersistence()
        logSubtitleAdjustmentIfNeeded()
    }

    private func setSubtitleDelay(_ delay: Double) {
        guard subtitleDelay != delay else { return }
        subtitleDelay = delay
        subtitleAdjustmentSettingsDidChange = true
        player.setSubtitleDelay(subtitleDelay)
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        scheduleSubtitleAdjustmentPersistence()
        logSubtitleAdjustmentIfNeeded()
    }

    private func applySubtitleAdjustmentSettings() {
        player.setSubtitlePosition(subtitlePosition)
        player.setSubtitleScale(subtitleScale)
        player.setSubtitleBorderSize(subtitleBorderSize)
        player.setSubtitleDelay(subtitleDelay)
        controlsView.updateSubtitleAdjustment(position: subtitlePosition,
                                              scale: subtitleScale,
                                              borderSize: subtitleBorderSize,
                                              delay: subtitleDelay)
        updateRenderedSubtitleOutline()
        updateRenderedSubtitleTransform()
    }

    private func reapplySubtitleAdjustmentSettings(reason: String) {
        player.setSubtitlePosition(subtitlePosition)
        player.setSubtitleScale(subtitleScale)
        player.setSubtitleBorderSize(subtitleBorderSize)
        player.setSubtitleDelay(subtitleDelay)
        updateRenderedSubtitleOutline()
        updateRenderedSubtitleTransform()
        #if DEBUG
        NSLog(
            "EmbyPlayerSubtitleAdjustmentReapply reason=%@ position=%.2f scale=%.2f border=%.2f delay=%.2f",
            reason,
            subtitlePosition,
            subtitleScale,
            subtitleBorderSize,
            subtitleDelay
        )
        #endif
    }

    private func scheduleSubtitleAdjustmentReapply(reason: String, after delay: TimeInterval) {
        guard !didRequestClose else { return }
        reapplySubtitleAdjustmentWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.didRequestClose else { return }
            self.reapplySubtitleAdjustmentSettings(reason: reason)
        }
        reapplySubtitleAdjustmentWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelSubtitleAdjustmentReapply() {
        reapplySubtitleAdjustmentWorkItem?.cancel()
        reapplySubtitleAdjustmentWorkItem = nil
    }

    private func logSubtitleAdjustmentIfNeeded() {
        #if DEBUG
        let now = Date()
        if let lastSubtitleAdjustmentLogAt,
           now.timeIntervalSince(lastSubtitleAdjustmentLogAt) < 0.25
        {
            return
        }
        lastSubtitleAdjustmentLogAt = now
        NSLog(
            "EmbyPlayerSubtitleAdjustment position=%.2f scale=%.2f border=%.2f delay=%.2f",
            subtitlePosition,
            subtitleScale,
            subtitleBorderSize,
            subtitleDelay
        )
        #endif
    }

    private func scheduleSubtitleAdjustmentPersistence() {
        persistSubtitleAdjustmentWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistSubtitleAdjustmentSettingsNow()
        }
        persistSubtitleAdjustmentWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func persistSubtitleAdjustmentSettingsNow() {
        persistSubtitleAdjustmentWorkItem?.cancel()
        persistSubtitleAdjustmentWorkItem = nil
        guard subtitleAdjustmentSettingsDidChange else { return }
        subtitleAdjustmentSettingsDidChange = false
        Defaults[.VideoPlayer.Subtitle.subtitlePosition] = subtitlePosition
        Defaults[.VideoPlayer.Subtitle.subtitleScale] = subtitleScale
        Defaults[.VideoPlayer.Subtitle.subtitleBorderSize] = subtitleBorderSize
        Defaults[.VideoPlayer.Subtitle.subtitleDelay] = subtitleDelay
    }

    private func loadSubtitleAdjustmentSettings(for item: BaseItemDto?) {
        subtitlePosition = Self.clampedSubtitlePosition(
            Defaults[.VideoPlayer.Subtitle.subtitlePosition]
        )
        subtitleScale = Self.clampedSubtitleScale(
            Defaults[.VideoPlayer.Subtitle.subtitleScale]
        )
        subtitleBorderSize = Self.clampedSubtitleBorderSize(
            Defaults[.VideoPlayer.Subtitle.subtitleBorderSize]
        )
        subtitleDelay = Defaults[.VideoPlayer.Subtitle.subtitleDelay]
        subtitleAdjustmentSettingsDidChange = false
    }

    private static func clampedSubtitlePosition(_ position: Double) -> Double {
        min(max(position, 0), 100)
    }

    private static func clampedSubtitleScale(_ scale: Double) -> Double {
        min(max(scale, 0.5), 2.5)
    }

    private static func clampedSubtitleBorderSize(_ borderSize: Double) -> Double {
        min(max(borderSize, 0), 8)
    }

    private func updateRenderedSubtitleOutline() {
        renderedSubtitleLabel.layer.shadowRadius = max(0, CGFloat(subtitleBorderSize + 1))
        renderedSubtitleLabel.layer.shadowOpacity = subtitleBorderSize > 0 ? 0.95 : 0
    }

    private func updateRenderedSubtitleTransform() {
        let liftFraction = CGFloat((100 - subtitlePosition) / 100)
        let maximumLift = max(view.bounds.height * 0.56, 0)
        renderedSubtitleLabel.transform = CGAffineTransform(translationX: 0, y: -maximumLift * liftFraction)
    }

    private func scheduleControlsHide(after delay: TimeInterval = 3) {
        cancelControlsHide()
        guard !keepsControlsVisibleForSmoke else { return }
        guard !controlsView.isSubtitleAdjustmentPanelVisible else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.controlsView.isSubtitleAdjustmentPanelVisible {
                self.hideControlsWorkItem = nil
                return
            }
            if self.controlsView.isSkipIntroAdjustmentActive {
                self.hideControlsWorkItem = nil
                return
            }
            self.hideControls()
            self.hideControlsWorkItem = nil
        }
        hideControlsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelControlsHide() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
    }

    private func scheduleVideoRectRefreshBurst() {
        let delays: [TimeInterval] = [0.0, 0.25, 1.0, 2.0, 4.0, 6.0, 8.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.player.refreshVideoRect()
            }
        }
    }

    private func scheduleForegroundRenderRefreshBurst(nudgeVideoOutput: Bool) {
        foregroundRenderRefreshGeneration += 1
        let generation = foregroundRenderRefreshGeneration
        let delays: [TimeInterval] = [0.0, 0.05, 0.15, 0.35, 0.75, 1.5]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      !self.didRequestClose,
                      self.foregroundRenderRefreshGeneration == generation
                else { return }

                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.playerView.refreshRenderingSurfaceForForeground()
                self.player.refreshVideoRect()

                #if DEBUG
                NSLog("EmbyPlayerBackground renderRefresh delay=%.2f bounds=%@ layer=%@ drawable=%@",
                      delay,
                      NSCoder.string(for: self.playerView.bounds),
                      NSCoder.string(for: self.playerView.metalLayer.frame),
                      NSCoder.string(for: self.playerView.metalLayer.drawableSize))
                self.logForegroundGeometry(reason: String(format: "renderRefresh-%.2f", delay))
                #endif
            }
        }

        if nudgeVideoOutput {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self,
                      !self.didRequestClose,
                      self.foregroundRenderRefreshGeneration == generation
                else { return }
                self.player.nudgeVideoOutputAfterForeground()
            }
        }
    }

    #if DEBUG
    private func logForegroundGeometry(reason: String) {
        if let foregroundGeometryLogUntil,
           Date() > foregroundGeometryLogUntil,
           reason == "videoRectChanged"
        {
            return
        }

        let rect = lastVideoRect
        let viewBounds = playerView.bounds
        let layerFrame = playerView.metalLayer.frame
        let drawable = playerView.metalLayer.drawableSize
        let scale = playerView.window?.screen.scale ?? UIScreen.main.scale
        let expectedDrawable = CGSize(width: viewBounds.width * scale, height: viewBounds.height * scale)

        NSLog(
            "EmbyPlayerGeometry reason=%@ view=%@ layer=%@ drawable=%@ expectedDrawable=%@ mpvRect={x=%.1f y=%.1f w=%.1f h=%.1f osd=%.1fx%.1f margins=%.1f/%.1f/%.1f/%.1f}",
            reason,
            NSCoder.string(for: viewBounds),
            NSCoder.string(for: layerFrame),
            NSCoder.string(for: drawable),
            NSCoder.string(for: expectedDrawable),
            rect?.x ?? -1,
            rect?.y ?? -1,
            rect?.width ?? -1,
            rect?.height ?? -1,
            rect?.osdWidth ?? -1,
            rect?.osdHeight ?? -1,
            rect?.marginLeft ?? -1,
            rect?.marginRight ?? -1,
            rect?.marginTop ?? -1,
            rect?.marginBottom ?? -1
        )
    }
    #endif

    private func handleLongPressSpeedGesture(state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            guard longPressSpeedRestoreValue == nil else { return }
            guard !player.isPaused else { return }
            let restoreSpeed = player.playbackSpeed
            longPressSpeedRestoreValue = restoreSpeed
            let fastSpeed = min(restoreSpeed * longPressSpeedMultiplier, 4.0)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            player.setPlaybackSpeed(fastSpeed)
            controlsView.updatePlaybackSpeed(fastSpeed)
            hideControls(animated: true)
            hideSeekPreviewNow()
            presentGestureHUD(symbol: "speedometer",
                              text: Self.formatSpeed(fastSpeed),
                              placement: .top,
                              style: .plainText,
                              autoHideAfter: 1.0)
        case .ended, .cancelled, .failed:
            guard let restoreSpeed = longPressSpeedRestoreValue else { return }
            longPressSpeedRestoreValue = nil
            player.setPlaybackSpeed(restoreSpeed)
            controlsView.updatePlaybackSpeed(restoreSpeed)
            scheduleGestureHUDHide(after: 1.0, preservingEarlierDeadline: true)
            scheduleControlsHide(after: 1.0)
        default:
            break
        }
    }

    private func cancelLongPressSpeedIfNeeded() {
        guard let restoreSpeed = longPressSpeedRestoreValue else { return }
        longPressSpeedRestoreValue = nil
        player.setPlaybackSpeed(restoreSpeed)
        controlsView.updatePlaybackSpeed(restoreSpeed)
        hideGestureHUDNow()
    }

    private func handleVerticalAdjustment(side: PlayerGestureController.VerticalAdjustmentSide,
                                          delta: Double,
                                          state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            verticalAdjustmentInitialValue = currentAdjustmentValue(for: side)
            cancelControlsHide()
            hideSeekPreviewNow()
            presentVerticalAdjustment(side: side, delta: 0)
        case .changed, .ended:
            presentVerticalAdjustment(side: side, delta: delta)
            if state == .ended {
                verticalAdjustmentInitialValue = nil
                scheduleGestureHUDHide(after: 0.45)
                scheduleControlsHide()
            }
        case .cancelled, .failed:
            verticalAdjustmentInitialValue = nil
            scheduleGestureHUDHide(after: 0.2)
            scheduleControlsHide()
        default:
            break
        }
    }

    private func presentVerticalAdjustment(side: PlayerGestureController.VerticalAdjustmentSide,
                                           delta: Double) {
        let initialValue = verticalAdjustmentInitialValue ?? currentAdjustmentValue(for: side)
        verticalAdjustmentInitialValue = initialValue
        let value = min(max(initialValue + delta * 1.15, 0), 1)
        setAdjustmentValue(value, for: side)
        let percent = Int((value * 100).rounded())
        presentGestureHUD(symbol: adjustmentSymbol(for: side),
                          text: "\(adjustmentTitle(for: side)) \(percent)%",
                          autoHideAfter: nil)
    }

    private func handleSeekGesture(delta seconds: Double, state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed:
            guard abs(seconds) >= 1 else {
                hideSeekPreviewNow()
                hideGestureHUDNow()
                return
            }
            cancelControlsHide()
            presentSeekGesturePreview(delta: seconds)
        case .ended:
            guard abs(seconds) >= 1 else {
                hideSeekPreviewNow()
                hideGestureHUDNow()
                return
            }
            presentSeekGesturePreview(delta: seconds)
            scheduleGestureHUDHide(after: 1.0)
            scheduleSeekTimelinePreviewEnd(after: 1.0)
        case .cancelled, .failed:
            hideSeekPreviewNow()
            hideGestureHUDNow()
        default:
            break
        }
    }

    private func presentSeekGesturePreview(delta seconds: Double) {
        let target = targetTime(forSeekDelta: seconds)
        let duration = max(player.duration, target)
        let text = duration > 0
            ? "\(Self.formatHUDTime(target)) / \(Self.formatHUDTime(duration))"
            : Self.formatHUDTime(target)
        endSeekTimelinePreviewWorkItem?.cancel()
        endSeekTimelinePreviewWorkItem = nil
        controlsView.previewTimeline(time: target, duration: duration)
        controlsView.setSeekPreview(time: target, duration: duration, visible: false)
        presentGestureHUD(symbol: seconds >= 0 ? "goforward" : "gobackward",
                          text: text,
                          placement: .top,
                          style: .plainText,
                          autoHideAfter: nil)
    }

    private func targetTime(forSeekDelta seconds: Double) -> Double {
        let rawTarget = player.currentTime + seconds
        if player.duration > 0 {
            return min(max(0, rawTarget), player.duration)
        }
        return max(0, rawTarget)
    }

    private func scheduleSeekTimelinePreviewEnd(after delay: TimeInterval) {
        endSeekTimelinePreviewWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.controlsView.endTimelinePreview()
            self.endSeekTimelinePreviewWorkItem = nil
        }
        endSeekTimelinePreviewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleSeekPreviewHide(after delay: TimeInterval) {
        hideSeekPreviewWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.controlsView.setSeekPreview(time: self.player.currentTime,
                                             duration: self.player.duration,
                                             visible: false)
        }
        hideSeekPreviewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func hideSeekPreviewNow() {
        hideSeekPreviewWorkItem?.cancel()
        hideSeekPreviewWorkItem = nil
        endSeekTimelinePreviewWorkItem?.cancel()
        endSeekTimelinePreviewWorkItem = nil
        controlsView.endTimelinePreview()
        controlsView.setSeekPreview(time: player.currentTime, duration: player.duration, visible: false)
    }

    private func hideGestureHUDNow() {
        hideGestureHUDWorkItem?.cancel()
        hideGestureHUDWorkItem = nil
        hideGestureHUDDeadline = nil
        hideGestureHUDGeneration += 1
        controlsView.setGestureHUD(symbol: "circle", text: "", visible: false)
    }

    private func presentGestureHUD(symbol: String,
                                   text: String,
                                   placement: PlayerControlsView.GestureHUDPlacement = .center,
                                   style: PlayerControlsView.GestureHUDStyle = .panel,
                                   autoHideAfter delay: TimeInterval?) {
        hideGestureHUDWorkItem?.cancel()
        hideGestureHUDWorkItem = nil
        hideGestureHUDDeadline = nil
        hideGestureHUDGeneration += 1
        controlsView.setGestureHUD(symbol: symbol,
                                   text: text,
                                   visible: true,
                                   placement: placement,
                                   style: style)

        if let delay {
            scheduleGestureHUDHide(after: delay)
        }
    }

    private func scheduleGestureHUDHide(after delay: TimeInterval, preservingEarlierDeadline: Bool = false) {
        let deadline = Date().addingTimeInterval(delay)
        if preservingEarlierDeadline,
           let existingDeadline = hideGestureHUDDeadline,
           existingDeadline <= deadline,
           hideGestureHUDWorkItem != nil {
            return
        }

        hideGestureHUDWorkItem?.cancel()
        hideGestureHUDGeneration += 1
        let generation = hideGestureHUDGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hideGestureHUDGeneration == generation else { return }
            self.controlsView.setGestureHUD(symbol: "circle", text: "", visible: false)
            self.hideGestureHUDWorkItem = nil
            self.hideGestureHUDDeadline = nil
        }
        hideGestureHUDWorkItem = item
        hideGestureHUDDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private static func formatHUDTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func currentAdjustmentValue(for side: PlayerGestureController.VerticalAdjustmentSide) -> Double {
        switch side {
        case .brightness:
            return Double(UIScreen.main.brightness)
        case .volume:
            return currentSystemVolume()
        }
    }

    private func setAdjustmentValue(_ value: Double, for side: PlayerGestureController.VerticalAdjustmentSide) {
        switch side {
        case .brightness:
            UIScreen.main.brightness = CGFloat(value)
        case .volume:
            setSystemVolume(value)
        }
    }

    @discardableResult
    private func resolveVolumeSlider() -> UISlider? {
        if let volumeSlider {
            return volumeSlider
        }
        let slider = Self.findVolumeSlider(in: volumeView)
        volumeSlider = slider
        return slider
    }

    private func currentSystemVolume() -> Double {
        if let slider = resolveVolumeSlider() {
            return Double(slider.value)
        }
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }

    private func setSystemVolume(_ value: Double) {
        let clampedValue = min(max(value, 0), 1)
        guard let slider = resolveVolumeSlider() else { return }
        slider.setValue(Float(clampedValue), animated: false)
        slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
    }

    private func adjustmentSymbol(for side: PlayerGestureController.VerticalAdjustmentSide) -> String {
        switch side {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            return "speaker.wave.2.fill"
        }
    }

    private func adjustmentTitle(for side: PlayerGestureController.VerticalAdjustmentSide) -> String {
        switch side {
        case .brightness:
            return "亮度"
        case .volume:
            return "音量"
        }
    }

    private func presentError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "播放错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func mpvTrackID(for stream: MediaStream, in streams: [MediaStream]) -> String? {
        guard let position = streams.firstIndex(where: { mediaStream($0, matchesOriginalOrAdjustedIndexesOf: stream) }) else {
            #if DEBUG
            NSLog("EmbyPlayerTrackMapMissing embyIndex=%d originalIndex=%d title=%@",
                  stream.index ?? -1,
                  stream.originalIndex ?? -1,
                  stream.displayTitle ?? stream.title ?? stream.language ?? "<nil>")
            #endif
            return nil
        }

        return String(position + 1)
    }

    private func mediaStream(_ candidate: MediaStream, matchesOriginalOrAdjustedIndexesOf stream: MediaStream) -> Bool {
        let indexes = [stream.index, stream.originalIndex].compactMap(\.self)
        return indexes.contains { candidate.index == $0 || candidate.originalIndex == $0 }
    }

    private static func findVolumeSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider {
            return slider
        }

        for subview in view.subviews {
            if let slider = findVolumeSlider(in: subview) {
                return slider
            }
        }

        return nil
    }

    private static func formatSpeed(_ speed: Double) -> String {
        let rounded = (speed * 100).rounded() / 100
        if abs(rounded.rounded() - rounded) < 0.001 {
            return String(format: "%.0fx", rounded)
        }
        if abs((rounded * 10).rounded() - rounded * 10) < 0.001 {
            return String(format: "%.1fx", rounded)
        }
        return String(format: "%.2fx", rounded)
    }

    private var longPressSpeedMultiplier: Double {
        let rawValue = Double(Defaults[.VideoPlayer.Gesture.longPressSpeedMultiplier].rawValue)
        guard rawValue.isFinite else { return 2.0 }
        return min(max(rawValue, 1.25), 4.0)
    }
}
