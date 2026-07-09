import UIKit

private final class CenteredCaretTextField: UITextField {
    override func layoutSubviews() {
        super.layoutSubviews()
        clearEditingBackgrounds(in: self)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        clearEditingBackgrounds(in: self)
        return becameFirstResponder
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        let rect = super.caretRect(for: position)
        guard (text ?? "").isEmpty else { return rect }
        return CGRect(
            x: (bounds.width - rect.width) / 2,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func clearEditingBackgrounds(in view: UIView) {
        for subview in view.subviews {
            subview.backgroundColor = .clear
            subview.layer.backgroundColor = UIColor.clear.cgColor
            clearEditingBackgrounds(in: subview)
        }
    }
}

final class PlayerControlsView: UIView, UITextFieldDelegate {
    enum GestureHUDPlacement: Equatable {
        case center
        case top
    }

    enum GestureHUDStyle: Equatable {
        case panel
        case plainText
    }

    enum SubtitleAdjustmentMode: Equatable {
        case position
        case scale
        case border
        case delay
    }

    private static let pausedIndicatorVisibleDuration: TimeInterval = 0.5
    private static let pausedIndicatorFadeOutDuration: TimeInterval = 0.5
    private static let pausedIndicatorFadeInDuration: TimeInterval = 0.18
    private static let bottomButtonSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
    private static let playButtonSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
    private static let jumpButtonSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    private static let bottomButtonSize = CGSize(width: 42, height: 46)
    private static let playButtonSize = CGSize(width: 50, height: 50)
    private static let subtitlePositionBaseline = 100.0
    private static let subtitlePositionStep = 1.0
    private static let subtitleScaleStep = 0.01
    private static let subtitleBorderSizeStep = 0.1
    private static let subtitleDelayStep = 0.1

    private enum JumpDirection {
        case backward
        case forward

        var baseSystemImage: String {
            switch self {
            case .backward:
                "gobackward"
            case .forward:
                "goforward"
            }
        }

        func systemImage(for interval: MediaJumpInterval) -> String {
            switch self {
            case .backward:
                interval.secondarySystemImage
            case .forward:
                interval.systemImage
            }
        }
    }

    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    var onOpenFolder: (() -> Void)? {
        didSet { updateOpenMenu() }
    }
    var onPlayPause: (() -> Void)?
    var onSeekBegan: (() -> Void)?
    var onSeekChanged: ((Double) -> Void)?
    var onSeekEnded: ((Double) -> Void)?
    var onPreviousEpisode: (() -> Void)?
    var onSeekBackward: (() -> Void)?
    var onSeekForward: (() -> Void)?
    var onSkipIntro: ((Double) -> Void)?
    var onSkipIntroAdjustmentCommitted: ((Int) -> Void)?
    var onSkipIntroReverseBegan: (() -> Void)?
    var onSkipIntroReverseEnded: (() -> Void)?
    var onNextEpisode: (() -> Void)?
    var onEpisodeList: (() -> Void)?
    var onPlaybackSpeedSelected: ((Double) -> Void)?
    var onMenuOpened: (() -> Void)?
    var onMenuSelectionFinished: (() -> Void)?
    var onOpenSubtitle: (() -> Void)? {
        didSet { updateSubtitleMenu() }
    }
    var onSelectSubtitleTrack: ((String) -> Void)?
    var onDisableSubtitle: (() -> Void)? {
        didSet { updateSubtitleMenu() }
    }
    var onSubtitlePositionChanged: ((Double) -> Void)?
    var onSubtitleScaleChanged: ((Double) -> Void)?
    var onSubtitleBorderSizeChanged: ((Double) -> Void)?
    var onSubtitleDelayChanged: ((Double) -> Void)?
    var onSubtitleAdjustmentBegan: (() -> Void)?
    var onSubtitleAdjustmentEnded: (() -> Void)?
    var onSubtitleAdjustmentVisibilityChanged: ((Bool) -> Void)?

    private let topBar = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let bottomBar = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let openButton = UIButton(type: .system)
    private let networkSpeedLabel = UILabel()
    private let clockLabel = UILabel()
    private let wifiStatusLabel = UILabel()
    private let batteryPercentLabel = UILabel()
    private let statusAccessoryStack = UIStackView()
    private let batteryIconContainer = UIView()
    private let batteryImageView = UIImageView()
    private let batteryChargingImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let previousEpisodeButton = UIButton(type: .system)
    private let seekBackwardButton = UIButton(type: .system)
    private let seekForwardButton = UIButton(type: .system)
    private let leftSkipIntroButton = UIButton(type: .system)
    private let rightSkipIntroButton = UIButton(type: .system)
    private let nextEpisodeButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let tracksButton = UIButton(type: .system)
    private let episodeListButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()
    private let cacheProgressView = UIProgressView(progressViewStyle: .bar)
    private let skipIntroStack = UIStackView()
    private let seekPreviewView = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let seekPreviewLabel = UILabel()
    private let gestureHUDView = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let gestureHUDIconView = UIImageView()
    private let gestureHUDLabel = UILabel()
    private let pausedIndicatorView = UIImageView(image: UIImage(systemName: "pause.fill"))
    private let renderedSubtitleLabel = UILabel()
    private let subtitleAdjustmentPanel = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let subtitleAdjustmentValueField = CenteredCaretTextField()
    private let subtitleAdjustmentIncreaseButton = UIButton(type: .system)
    private let subtitleAdjustmentSliderContainer = UIView()
    private let subtitleAdjustmentSlider = UISlider()
    private let subtitleAdjustmentDecreaseButton = UIButton(type: .system)
    private let subtitleAdjustmentIconView = UIImageView()
    private let subtitleAdjustmentStack = UIStackView()

    private var trackingSlider = false
    private var previewingTimeline = false
    private var mediaDuration = 0.0
    private var cachedTime = 0.0
    private var currentPlaybackSpeed = 1.0
    private var isPaused = false
    private var areControlsHidden = false
    private var skipIntroButtonsDismissed = false
    private var skipIntroSeconds = 70
    private var skipIntroAdjustmentSeconds = 70
    private var skipIntroAdjustmentActive = false
    private var skipIntroAdjustmentHasJumpedDefault = false
    private var skipIntroAdjustmentShouldResumePlayback = false
    private var skipIntroAdjustmentCommitWorkItem: DispatchWorkItem?
    private var skipIntroAdjustmentRepeatTimer: Timer?
    private var pausedIndicatorHideWorkItem: DispatchWorkItem?
    private var pausedIndicatorVisibilityGeneration = 0
    private var pausedIndicatorSuppressedUntil: Date?
    private var subtitleTracks: [MPVSubtitleTrack] = []
    private var selectedSubtitleID: String?
    private var controlsVisibilityGeneration = 0
    private var currentGestureHUDPlacement: GestureHUDPlacement = .center
    private var currentGestureHUDStyle: GestureHUDStyle = .panel
    private var subtitleAdjustmentMode: SubtitleAdjustmentMode = .position
    private var subtitleAdjustmentPanelVisible = false
    private var subtitleAdjustmentVisibilityGeneration = 0
    private var subtitlePosition = 100.0
    private var subtitleScale = 1.0
    private var subtitleBorderSize = 3.0
    private var subtitleDelay = 0.0
    private var gestureHUDCenterYConstraint: NSLayoutConstraint?
    private var gestureHUDTopConstraint: NSLayoutConstraint?
    private var subtitleVisibleBottomConstraint: NSLayoutConstraint?
    private var subtitleControlsBottomConstraint: NSLayoutConstraint?
    private var clockTimer: Timer?
    private var wasBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        skipIntroAdjustmentRepeatTimer?.invalidate()
        skipIntroAdjustmentCommitWorkItem?.cancel()
        clockTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled
    }

    func setPaused(_ paused: Bool, showsIndicator: Bool = true) {
        isPaused = paused
        let symbol = paused ? "play.fill" : "pause.fill"
        setButtonImage(playPauseButton, symbol: symbol)
        playPauseButton.accessibilityLabel = paused ? "Play" : "Pause"
        updatePausedIndicator(animated: true, allowsShowing: showsIndicator)
    }

    func suppressPausedIndicatorTemporarily(duration: TimeInterval = 1.0) {
        pausedIndicatorSuppressedUntil = Date().addingTimeInterval(duration)
        updatePausedIndicator(animated: false, allowsShowing: false)
    }

    func update(time: Double, duration: Double) {
        mediaDuration = duration
        guard !trackingSlider && !previewingTimeline else { return }
        updateTimeline(time: time, duration: duration)
    }

    func updateCachedTime(_ cachedTime: Double) {
        self.cachedTime = cachedTime
        updateCacheProgress()
    }

    func updateCacheSpeed(_ bytesPerSecond: Double) {
        networkSpeedLabel.text = Self.formatNetworkSpeed(bytesPerSecond)
    }

    func previewTimeline(time: Double, duration: Double) {
        previewingTimeline = true
        mediaDuration = duration
        updateTimeline(time: time, duration: duration)
    }

    func endTimelinePreview() {
        previewingTimeline = false
    }

    private func updateTimeline(time: Double, duration: Double) {
        mediaDuration = duration
        currentTimeLabel.text = Self.formatTime(time)
        durationLabel.text = Self.formatTime(duration)
        slider.maximumValue = Float(max(duration, 1))
        slider.value = Float(min(max(time, 0), max(duration, 1)))
        updateCacheProgress()
    }

    private func updateCacheProgress() {
        guard mediaDuration > 0, cachedTime.isFinite else {
            cacheProgressView.progress = 0
            return
        }

        let progress = min(max(cachedTime / mediaDuration, 0), 1)
        cacheProgressView.setProgress(Float(progress), animated: false)
    }

    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        controlsVisibilityGeneration += 1
        let generation = controlsVisibilityGeneration
        areControlsHidden = hidden
        if !hidden {
            topBar.isHidden = false
            bottomBar.isHidden = false
            skipIntroStack.isHidden = skipIntroButtonsDismissed
            topBar.isUserInteractionEnabled = true
            bottomBar.isUserInteractionEnabled = true
            skipIntroStack.isUserInteractionEnabled = !skipIntroButtonsDismissed
        }

        let changes = {
            self.topBar.alpha = hidden ? 0 : 1
            self.bottomBar.alpha = hidden ? 0 : 1
            self.skipIntroStack.alpha = (hidden && !self.skipIntroAdjustmentActive) || self.skipIntroButtonsDismissed ? 0 : 1
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.controlsVisibilityGeneration == generation else { return }
            self.topBar.isHidden = hidden
            self.bottomBar.isHidden = hidden
            self.skipIntroStack.isHidden = (hidden && !self.skipIntroAdjustmentActive) || self.skipIntroButtonsDismissed
            self.topBar.isUserInteractionEnabled = !hidden
            self.bottomBar.isUserInteractionEnabled = !hidden
            self.skipIntroStack.isUserInteractionEnabled = (!hidden || self.skipIntroAdjustmentActive) && !self.skipIntroButtonsDismissed
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
        updateRenderedSubtitlePosition(controlsHidden: hidden)
        updatePausedIndicator(animated: animated, allowsShowing: false)
    }

    func updateSubtitleTracks(_ tracks: [MPVSubtitleTrack], selectedID: String?) {
        subtitleTracks = tracks
        selectedSubtitleID = selectedID
        updateSubtitleMenu()
    }

    func updateSubtitleAdjustment(position: Double, scale: Double, borderSize: Double? = nil, delay: Double? = nil) {
        let nextPosition = min(max(position, 0), 100)
        let nextScale = min(max(scale, 0.5), 2.5)
        let nextBorderSize = borderSize.map(Self.clampedSubtitleBorderSize) ?? subtitleBorderSize
        let nextDelay = delay ?? subtitleDelay
        guard subtitlePosition != nextPosition ||
            subtitleScale != nextScale ||
            subtitleBorderSize != nextBorderSize ||
            subtitleDelay != nextDelay
        else { return }

        subtitlePosition = nextPosition
        subtitleScale = nextScale
        if borderSize != nil {
            subtitleBorderSize = nextBorderSize
        }
        if delay != nil {
            subtitleDelay = nextDelay
        }
        updateSubtitleAdjustmentSlider(animated: false)
        updateSubtitleAdjustmentValueDisplays(forceField: false)
    }

    func setSubtitleAdjustmentPanelVisible(_ visible: Bool, animated: Bool) {
        guard subtitleAdjustmentPanelVisible != visible else { return }
        subtitleAdjustmentVisibilityGeneration += 1
        let generation = subtitleAdjustmentVisibilityGeneration
        subtitleAdjustmentPanelVisible = visible
        setControlsHidden(true, animated: animated)
        updateSubtitleMenu()
        updateSettingsMenu()
        updatePausedIndicator(animated: animated, allowsShowing: false)

        if visible {
            subtitleAdjustmentPanel.isHidden = false
            subtitleAdjustmentPanel.isUserInteractionEnabled = true
            updateSubtitleAdjustmentSlider(animated: false)
        }

        let changes = {
            self.subtitleAdjustmentPanel.alpha = visible ? 1 : 0
            self.subtitleAdjustmentPanel.transform = visible ? .identity : CGAffineTransform(translationX: 18, y: 0)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.subtitleAdjustmentVisibilityGeneration == generation else { return }
            self.subtitleAdjustmentPanel.isHidden = !self.subtitleAdjustmentPanelVisible
            self.subtitleAdjustmentPanel.isUserInteractionEnabled = self.subtitleAdjustmentPanelVisible
        }

        if animated {
            UIView.animate(withDuration: visible ? 0.18 : 0.14,
                           delay: 0,
                           options: [.beginFromCurrentState, .curveEaseOut],
                           animations: changes,
                           completion: completion)
        } else {
            changes()
            completion(true)
        }

        onSubtitleAdjustmentVisibilityChanged?(visible)
    }

    func toggleSubtitleAdjustmentPanel() {
        setSubtitleAdjustmentPanelVisible(!subtitleAdjustmentPanelVisible, animated: true)
    }

    func showSubtitleAdjustmentPanel(mode: SubtitleAdjustmentMode, animated: Bool) {
        setSubtitleAdjustmentMode(mode)
        setSubtitleAdjustmentPanelVisible(true, animated: animated)
    }

    func closeSubtitleAdjustmentForPlayerDismissal() {
        guard needsSubtitleAdjustmentDismissalForPlayerDismissal else { return }
        subtitleAdjustmentVisibilityGeneration += 1
        if subtitleAdjustmentValueField.isFirstResponder {
            endEditing(true)
            subtitleAdjustmentValueField.resignFirstResponder()
        }
        subtitleAdjustmentPanel.layer.removeAllAnimations()
        subtitleAdjustmentPanelVisible = false
        subtitleAdjustmentPanel.alpha = 0
        subtitleAdjustmentPanel.transform = CGAffineTransform(translationX: 18, y: 0)
        subtitleAdjustmentPanel.isHidden = true
        subtitleAdjustmentPanel.isUserInteractionEnabled = false
        setControlsHidden(true, animated: false)
    }

    func updateRenderedSubtitle(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            UIView.animate(withDuration: 0.12) {
                self.renderedSubtitleLabel.alpha = 0
            }
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        renderedSubtitleLabel.attributedText = NSAttributedString(
            string: trimmed,
            attributes: [
                .font: UIFont.systemFont(ofSize: 27, weight: .semibold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.5,
                .paragraphStyle: paragraphStyle,
            ]
        )
        UIView.animate(withDuration: 0.08) {
            self.renderedSubtitleLabel.alpha = 1
        }
    }

    func updatePlaybackSpeed(_ speed: Double) {
        currentPlaybackSpeed = speed
        speedButton.accessibilityValue = Self.formatSpeed(speed)
        updateSpeedMenu()
    }

    func updateJumpIntervals(backward: MediaJumpInterval, forward: MediaJumpInterval) {
        setJumpButtonImage(seekBackwardButton, interval: backward, direction: .backward)
        seekBackwardButton.accessibilityLabel = "Back \(Self.formatDuration(backward.rawValue))"
        setJumpButtonImage(seekForwardButton, interval: forward, direction: .forward)
        seekForwardButton.accessibilityLabel = "Forward \(Self.formatDuration(forward.rawValue))"
    }

    func setSkipIntroDismissed(_ dismissed: Bool) {
        skipIntroButtonsDismissed = dismissed
        if dismissed {
            cancelSkipIntroAdjustment()
        }
        skipIntroStack.alpha = areControlsHidden || dismissed ? 0 : 1
        skipIntroStack.isHidden = areControlsHidden || dismissed
        skipIntroStack.isUserInteractionEnabled = !areControlsHidden && !dismissed
    }

    func updateSkipIntroSeconds(_ seconds: Int) {
        skipIntroSeconds = max(5, seconds)
        if !skipIntroAdjustmentActive {
            skipIntroAdjustmentSeconds = skipIntroSeconds
            updateSkipIntroTitles(adjusting: false)
        }
    }

    func updateEpisodeNavigation(canGoPrevious: Bool, canGoNext: Bool, canShowEpisodeList: Bool) {
        setNavigationButton(previousEpisodeButton, enabled: canGoPrevious)
        setNavigationButton(nextEpisodeButton, enabled: canGoNext)
        setNavigationButton(episodeListButton, enabled: canShowEpisodeList)
    }

    func updateTitle(_ title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
    }

    func triggerMenuOpenForSmoke() {
        onMenuOpened?()
    }

    var seekPreviewVisibleForSmoke: Bool {
        seekPreviewView.alpha > 0.01
    }

    var seekPreviewAlphaForSmoke: CGFloat {
        seekPreviewView.alpha
    }

    var gestureHUDVisibleForSmoke: Bool {
        gestureHUDView.alpha > 0.01
    }

    var gestureHUDTextForSmoke: String {
        gestureHUDLabel.text ?? ""
    }

    var gestureHUDUsesPlainTopStyleForSmoke: Bool {
        currentGestureHUDPlacement == .top && currentGestureHUDStyle == .plainText
    }

    var controlsVisibleForSmoke: Bool {
        (!topBar.isHidden && topBar.alpha > 0.01) || (!bottomBar.isHidden && bottomBar.alpha > 0.01)
    }

    var progressControlsVisibleForSmoke: Bool {
        !bottomBar.isHidden && bottomBar.alpha > 0.01
    }

    var subtitleAdjustmentPanelVisibleForSmoke: Bool {
        !subtitleAdjustmentPanel.isHidden && subtitleAdjustmentPanel.alpha > 0.01
    }

    var isSubtitleAdjustmentPanelVisible: Bool {
        subtitleAdjustmentPanelVisible
    }

    var needsSubtitleAdjustmentDismissalForPlayerDismissal: Bool {
        subtitleAdjustmentPanelVisible ||
            !subtitleAdjustmentPanel.isHidden ||
            subtitleAdjustmentPanel.alpha > 0.01 ||
            subtitleAdjustmentValueField.isFirstResponder
    }

    func shouldSuppressPlayerGesture(at point: CGPoint) -> Bool {
        guard subtitleAdjustmentPanelVisible,
              !subtitleAdjustmentPanel.isHidden,
              subtitleAdjustmentPanel.alpha > 0.01
        else { return false }

        let panelPoint = convert(point, to: subtitleAdjustmentPanel)
        return subtitleAdjustmentPanel.point(inside: panelPoint, with: nil)
    }

    var subtitleAdjustmentModeForSmoke: SubtitleAdjustmentMode {
        subtitleAdjustmentMode
    }

    var subtitleAdjustmentSliderValueForSmoke: Double {
        Double(subtitleAdjustmentSlider.value)
    }

    var subtitleAdjustmentInputTextForSmoke: String? {
        subtitleAdjustmentValueField.text
    }

    var subtitleAdjustmentValueFieldIsTopForSmoke: Bool {
        subtitleAdjustmentStack.arrangedSubviews.first === subtitleAdjustmentValueField
    }

    var subtitleAdjustmentIconLabelForSmoke: String? {
        subtitleAdjustmentIconView.accessibilityLabel
    }

    var subtitleAdjustmentStepButtonLabelsForSmoke: [String] {
        [
            subtitleAdjustmentIncreaseButton.accessibilityLabel,
            subtitleAdjustmentDecreaseButton.accessibilityLabel,
        ].compactMap { $0 }
    }

    #if DEBUG
    func setSubtitleAdjustmentModeForSmoke(_ mode: SubtitleAdjustmentMode) {
        setSubtitleAdjustmentMode(mode)
    }

    func showSubtitleAdjustmentPanelForSmoke(_ mode: SubtitleAdjustmentMode) {
        showSubtitleAdjustmentPanel(mode: mode, animated: false)
    }

    func triggerSubtitleAdjustmentIncreaseForSmoke() {
        stepSubtitleAdjustment(direction: 1)
    }

    func triggerSubtitleAdjustmentDecreaseForSmoke() {
        stepSubtitleAdjustment(direction: -1)
    }

    #endif

    var timelineValueForSmoke: Double {
        Double(slider.value)
    }

    @discardableResult
    func triggerSliderDragForSmoke(toFraction fraction: Float) -> Double {
        let clampedFraction = min(max(fraction, 0), 1)
        let range = slider.maximumValue - slider.minimumValue
        sliderTouchDown()
        slider.value = slider.minimumValue + range * clampedFraction
        sliderValueChanged()
        sliderTouchEnded()
        return Double(slider.value)
    }

    func setSeekPreview(time: Double, duration: Double, visible: Bool) {
        let current = Self.formatTime(time)
        if duration > 0 {
            seekPreviewLabel.text = "\(current) / \(Self.formatTime(duration))"
        } else {
            seekPreviewLabel.text = current
        }

        UIView.animate(withDuration: visible ? 0.12 : 0.16) {
            self.seekPreviewView.alpha = visible ? 1 : 0
        }
    }

    func setGestureHUD(symbol: String,
                       text: String,
                       visible: Bool,
                       placement: GestureHUDPlacement = .center,
                       style: GestureHUDStyle = .panel) {
        if visible {
            setGestureHUDPlacement(placement)
            setGestureHUDStyle(style)
            gestureHUDIconView.image = UIImage(systemName: symbol)
            gestureHUDIconView.isHidden = style == .plainText
            gestureHUDLabel.text = text
            gestureHUDLabel.textAlignment = style == .plainText ? .center : .left
        }

        UIView.animate(withDuration: visible ? 0.1 : 0.16) {
            self.gestureHUDView.alpha = visible ? 1 : 0
        }
    }

    private func configure() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        configureButton(openButton, symbol: "folder", label: "打开")
        configureButton(
            previousEpisodeButton,
            symbol: "backward.end.fill",
            label: "上一集",
            symbolConfiguration: Self.bottomButtonSymbolConfiguration
        )
        configureButton(
            seekBackwardButton,
            symbol: "gobackward.10",
            label: "后退 10 秒",
            symbolConfiguration: Self.jumpButtonSymbolConfiguration
        )
        configureButton(
            playPauseButton,
            symbol: "play.fill",
            label: "播放",
            symbolConfiguration: Self.playButtonSymbolConfiguration
        )
        configureButton(
            seekForwardButton,
            symbol: "goforward.10",
            label: "前进 10 秒",
            symbolConfiguration: Self.jumpButtonSymbolConfiguration
        )
        configureSkipIntroButton(leftSkipIntroButton)
        configureSkipIntroButton(rightSkipIntroButton)
        configureButton(
            nextEpisodeButton,
            symbol: "forward.end.fill",
            label: "下一集",
            symbolConfiguration: Self.bottomButtonSymbolConfiguration
        )
        configureButton(
            speedButton,
            symbol: "speedometer",
            label: "播放速度",
            symbolConfiguration: Self.bottomButtonSymbolConfiguration
        )
        configureButton(
            tracksButton,
            symbol: "captions.bubble",
            label: "字幕",
            symbolConfiguration: Self.bottomButtonSymbolConfiguration
        )
        configureButton(
            episodeListButton,
            symbol: "list.triangle",
            label: "选集",
            symbolConfiguration: Self.bottomButtonSymbolConfiguration
        )
        configureButton(settingsButton, symbol: "gearshape", label: "设置")
        applyIconShadow(to: settingsButton)
        configureStatusLabel(networkSpeedLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium))
        configureStatusLabel(clockLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium))
        configureWifiStatusLabel()
        configureStatusLabel(batteryPercentLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium))
        configureBatteryImageView()
        configureBatteryChargingImageView()
        networkSpeedLabel.text = Self.formatNetworkSpeed(0)
        networkSpeedLabel.accessibilityLabel = "网络速度"
        clockLabel.accessibilityLabel = "当前时间"
        startStatusUpdates()
        configureTitleLabel(titleLabel, font: .systemFont(ofSize: 16, weight: .semibold))
        configureTitleLabel(subtitleLabel, font: .systemFont(ofSize: 12, weight: .medium))
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.isHidden = true

        previousEpisodeButton.addTarget(self, action: #selector(previousEpisodeTapped), for: .touchUpInside)
        seekBackwardButton.addTarget(self, action: #selector(seekBackwardTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        seekForwardButton.addTarget(self, action: #selector(seekForwardTapped), for: .touchUpInside)
        leftSkipIntroButton.addTarget(self, action: #selector(skipIntroTapped), for: .touchUpInside)
        rightSkipIntroButton.addTarget(self, action: #selector(skipIntroTapped), for: .touchUpInside)
        let leftSkipIntroLongPress = UILongPressGestureRecognizer(target: self, action: #selector(skipIntroLongPressed(_:)))
        let rightSkipIntroLongPress = UILongPressGestureRecognizer(target: self, action: #selector(skipIntroLongPressed(_:)))
        leftSkipIntroLongPress.minimumPressDuration = 0.35
        rightSkipIntroLongPress.minimumPressDuration = 0.35
        leftSkipIntroButton.addGestureRecognizer(leftSkipIntroLongPress)
        rightSkipIntroButton.addGestureRecognizer(rightSkipIntroLongPress)
        nextEpisodeButton.addTarget(self, action: #selector(nextEpisodeTapped), for: .touchUpInside)
        episodeListButton.addTarget(self, action: #selector(episodeListTapped), for: .touchUpInside)
        configureOpenMenu()
        configureSpeedMenu()
        configureTracksMenu()
        configureSettingsMenu()
        updateEpisodeNavigation(canGoPrevious: false, canGoNext: false, canShowEpisodeList: false)

        configureTimeLabel(currentTimeLabel)
        configureTimeLabel(durationLabel)
        currentTimeLabel.text = "00:00"
        durationLabel.text = "00:00"

        configurePanel(topBar, drawsBackground: false)
        configurePanel(bottomBar, drawsBackground: true)
        configureSeekPreview()
        configureGestureHUD()
        configurePausedIndicator()
        configureSubtitleAdjustmentPanel()
        configureRenderedSubtitleLabel()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .clear
        slider.thumbTintColor = .white
        applyShadow(to: slider.layer, opacity: 0.45, radius: 3, offset: CGSize(width: 0, height: 1))
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        cacheProgressView.progress = 0
        cacheProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.18)
        cacheProgressView.progressTintColor = UIColor.white.withAlphaComponent(0.36)
        cacheProgressView.layer.cornerRadius = 2
        cacheProgressView.clipsToBounds = true
        cacheProgressView.isUserInteractionEnabled = false

        addSubview(topBar)
        addSubview(bottomBar)
        addSubview(seekPreviewView)
        addSubview(gestureHUDView)
        addSubview(pausedIndicatorView)
        addSubview(renderedSubtitleLabel)
        addSubview(subtitleAdjustmentPanel)

        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        seekPreviewView.translatesAutoresizingMaskIntoConstraints = false
        gestureHUDView.translatesAutoresizingMaskIntoConstraints = false
        pausedIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        renderedSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleAdjustmentPanel.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topStack = UIStackView(arrangedSubviews: [openButton, titleStack, settingsButton])
        topStack.axis = .horizontal
        topStack.alignment = .center
        topStack.spacing = 16
        topStack.distribution = .fill
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(networkSpeedLabel)
        topBar.contentView.addSubview(clockLabel)
        statusAccessoryStack.axis = .horizontal
        statusAccessoryStack.alignment = .center
        statusAccessoryStack.spacing = 4
        statusAccessoryStack.translatesAutoresizingMaskIntoConstraints = false
        statusAccessoryStack.addArrangedSubview(wifiStatusLabel)
        statusAccessoryStack.addArrangedSubview(batteryPercentLabel)
        statusAccessoryStack.addArrangedSubview(batteryIconContainer)
        batteryIconContainer.addSubview(batteryImageView)
        batteryIconContainer.addSubview(batteryChargingImageView)
        topBar.contentView.addSubview(statusAccessoryStack)
        topBar.contentView.addSubview(topStack)
        networkSpeedLabel.translatesAutoresizingMaskIntoConstraints = false
        clockLabel.translatesAutoresizingMaskIntoConstraints = false
        batteryIconContainer.translatesAutoresizingMaskIntoConstraints = false
        batteryImageView.translatesAutoresizingMaskIntoConstraints = false
        batteryChargingImageView.translatesAutoresizingMaskIntoConstraints = false

        let transportStack = UIStackView(arrangedSubviews: [
            previousEpisodeButton,
            seekBackwardButton,
            playPauseButton,
            seekForwardButton,
            nextEpisodeButton,
            tracksButton,
            speedButton,
            episodeListButton
        ])
        transportStack.axis = .horizontal
        transportStack.alignment = .center
        transportStack.distribution = .equalSpacing
        transportStack.spacing = 6
        transportStack.translatesAutoresizingMaskIntoConstraints = false

        let sliderContainer = UIView()
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        cacheProgressView.translatesAutoresizingMaskIntoConstraints = false
        sliderContainer.addSubview(cacheProgressView)
        sliderContainer.addSubview(slider)

        let timelineStack = UIStackView(arrangedSubviews: [currentTimeLabel, sliderContainer, durationLabel])
        timelineStack.axis = .horizontal
        timelineStack.alignment = .center
        timelineStack.spacing = 10
        timelineStack.translatesAutoresizingMaskIntoConstraints = false

        let skipIntroSpacer = UIView()
        skipIntroSpacer.translatesAutoresizingMaskIntoConstraints = false
        skipIntroStack.addArrangedSubview(leftSkipIntroButton)
        skipIntroStack.addArrangedSubview(skipIntroSpacer)
        skipIntroStack.addArrangedSubview(rightSkipIntroButton)
        skipIntroStack.axis = .horizontal
        skipIntroStack.alignment = .center
        skipIntroStack.spacing = 8
        skipIntroStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomStack = UIStackView(arrangedSubviews: [timelineStack, transportStack])
        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skipIntroStack)
        bottomBar.contentView.addSubview(bottomStack)

        let gestureHUDCenterYConstraint = gestureHUDView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24)
        let gestureHUDTopConstraint = gestureHUDView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 72)
        self.gestureHUDCenterYConstraint = gestureHUDCenterYConstraint
        self.gestureHUDTopConstraint = gestureHUDTopConstraint
        let subtitleVisibleBottomConstraint = renderedSubtitleLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -34)
        let subtitleControlsBottomConstraint = renderedSubtitleLabel.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14)
        self.subtitleVisibleBottomConstraint = subtitleVisibleBottomConstraint
        self.subtitleControlsBottomConstraint = subtitleControlsBottomConstraint
        let subtitleAdjustmentPanelHeightConstraint = subtitleAdjustmentPanel.heightAnchor.constraint(equalToConstant: 286)
        subtitleAdjustmentPanelHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            networkSpeedLabel.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 4),
            networkSpeedLabel.centerYAnchor.constraint(equalTo: clockLabel.centerYAnchor),
            networkSpeedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            networkSpeedLabel.trailingAnchor.constraint(lessThanOrEqualTo: clockLabel.leadingAnchor, constant: -12),
            clockLabel.centerXAnchor.constraint(equalTo: topBar.contentView.centerXAnchor),
            clockLabel.topAnchor.constraint(equalTo: topBar.contentView.topAnchor),
            clockLabel.heightAnchor.constraint(equalToConstant: 18),
            statusAccessoryStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -4),
            statusAccessoryStack.centerYAnchor.constraint(equalTo: clockLabel.centerYAnchor),
            wifiStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            wifiStatusLabel.heightAnchor.constraint(equalToConstant: 16),
            batteryIconContainer.widthAnchor.constraint(equalToConstant: 25),
            batteryIconContainer.heightAnchor.constraint(equalToConstant: 16),
            batteryImageView.leadingAnchor.constraint(equalTo: batteryIconContainer.leadingAnchor),
            batteryImageView.centerYAnchor.constraint(equalTo: batteryIconContainer.centerYAnchor),
            batteryImageView.widthAnchor.constraint(equalToConstant: 25),
            batteryImageView.heightAnchor.constraint(equalToConstant: 14),
            batteryChargingImageView.centerXAnchor.constraint(equalTo: batteryIconContainer.centerXAnchor, constant: -1),
            batteryChargingImageView.centerYAnchor.constraint(equalTo: batteryIconContainer.centerYAnchor),
            batteryChargingImageView.widthAnchor.constraint(equalToConstant: 8),
            batteryChargingImageView.heightAnchor.constraint(equalToConstant: 10),
            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 10),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -10),
            topStack.topAnchor.constraint(equalTo: clockLabel.bottomAnchor),
            topStack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -6),
            titleStack.centerXAnchor.constraint(equalTo: topBar.contentView.centerXAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: openButton.trailingAnchor, constant: 16),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -16),

            bottomBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            bottomBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            skipIntroStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            skipIntroStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            skipIntroStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -12),
            bottomStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            bottomStack.bottomAnchor.constraint(equalTo: bottomBar.contentView.bottomAnchor, constant: -4),
            transportStack.centerXAnchor.constraint(equalTo: bottomStack.centerXAnchor),
            leftSkipIntroButton.widthAnchor.constraint(equalToConstant: 96),
            leftSkipIntroButton.heightAnchor.constraint(equalToConstant: 32),
            rightSkipIntroButton.widthAnchor.constraint(equalToConstant: 96),
            rightSkipIntroButton.heightAnchor.constraint(equalToConstant: 32),
            timelineStack.heightAnchor.constraint(equalToConstant: 30),
            sliderContainer.heightAnchor.constraint(equalToConstant: 30),
            slider.leadingAnchor.constraint(equalTo: sliderContainer.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: sliderContainer.trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor),
            cacheProgressView.leadingAnchor.constraint(equalTo: sliderContainer.leadingAnchor),
            cacheProgressView.trailingAnchor.constraint(equalTo: sliderContainer.trailingAnchor),
            cacheProgressView.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            cacheProgressView.heightAnchor.constraint(equalToConstant: 4),

            playPauseButton.widthAnchor.constraint(equalToConstant: Self.playButtonSize.width),
            playPauseButton.heightAnchor.constraint(equalToConstant: Self.playButtonSize.height),
            previousEpisodeButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            previousEpisodeButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            seekBackwardButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            seekBackwardButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            seekForwardButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            seekForwardButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            nextEpisodeButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            nextEpisodeButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            speedButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            speedButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            openButton.widthAnchor.constraint(equalToConstant: 46),
            openButton.heightAnchor.constraint(equalToConstant: 46),
            tracksButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            tracksButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            episodeListButton.widthAnchor.constraint(equalToConstant: Self.bottomButtonSize.width),
            episodeListButton.heightAnchor.constraint(equalToConstant: Self.bottomButtonSize.height),
            settingsButton.widthAnchor.constraint(equalToConstant: 46),
            settingsButton.heightAnchor.constraint(equalToConstant: 46),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 56),
            durationLabel.widthAnchor.constraint(equalToConstant: 56),

            seekPreviewView.centerXAnchor.constraint(equalTo: centerXAnchor),
            seekPreviewView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 96),
            seekPreviewView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            seekPreviewView.widthAnchor.constraint(greaterThanOrEqualToConstant: 156),

            gestureHUDView.centerXAnchor.constraint(equalTo: centerXAnchor),
            gestureHUDCenterYConstraint,
            gestureHUDView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            gestureHUDView.widthAnchor.constraint(greaterThanOrEqualToConstant: 142),

            pausedIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            pausedIndicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pausedIndicatorView.widthAnchor.constraint(equalToConstant: 74),
            pausedIndicatorView.heightAnchor.constraint(equalToConstant: 74),

            subtitleAdjustmentPanel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            subtitleAdjustmentPanel.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            subtitleAdjustmentPanel.widthAnchor.constraint(equalToConstant: 72),
            subtitleAdjustmentPanelHeightConstraint,
            subtitleAdjustmentPanel.heightAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.heightAnchor, constant: -62),

            renderedSubtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            renderedSubtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 48),
            renderedSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -48),
            renderedSubtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.82),
            subtitleControlsBottomConstraint
        ])
    }

    private func setGestureHUDPlacement(_ placement: GestureHUDPlacement) {
        currentGestureHUDPlacement = placement
        switch placement {
        case .center:
            gestureHUDTopConstraint?.isActive = false
            gestureHUDCenterYConstraint?.isActive = true
        case .top:
            gestureHUDCenterYConstraint?.isActive = false
            gestureHUDTopConstraint?.isActive = true
        }
    }

    private func updateRenderedSubtitlePosition(controlsHidden: Bool) {
        subtitleControlsBottomConstraint?.isActive = !controlsHidden
        subtitleVisibleBottomConstraint?.isActive = controlsHidden
        UIView.animate(withDuration: 0.18) {
            self.layoutIfNeeded()
        }
    }

    private func setGestureHUDStyle(_ style: GestureHUDStyle) {
        currentGestureHUDStyle = style
        switch style {
        case .panel:
            gestureHUDView.effect = Self.panelEffect()
            configurePanel(gestureHUDView, drawsBackground: true)
            gestureHUDLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        case .plainText:
            gestureHUDView.effect = nil
            gestureHUDView.backgroundColor = .clear
            gestureHUDView.clipsToBounds = false
            gestureHUDView.layer.borderWidth = 0
            gestureHUDLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        }
    }

    private func configureButton(_ button: UIButton,
                                 symbol: String,
                                 label: String,
                                 symbolConfiguration: UIImage.SymbolConfiguration? = nil) {
        button.tintColor = .white
        button.accessibilityLabel = label
        button.adjustsImageSizeForAccessibilityContentSizeCategory = true
        let image = Self.systemImage(named: symbol, configuration: symbolConfiguration)

        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.clearGlass()
            configuration.image = image
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            configuration.baseForegroundColor = .white
            configuration.buttonSize = .large
            configuration.cornerStyle = .capsule
            button.configuration = configuration
        } else {
            button.setImage(image, for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            button.layer.cornerRadius = 22
            button.layer.cornerCurve = .continuous
            button.layer.masksToBounds = true
        }
    }

    private func configureSkipIntroButton(_ button: UIButton) {
        button.tintColor = .white
        button.accessibilityLabel = "跳过片头"
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)

        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.clearGlass()
            configuration.title = "跳过片头"
            configuration.baseForegroundColor = .white
            configuration.buttonSize = .small
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            button.configuration = configuration
        } else if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.filled()
            configuration.title = "跳过片头"
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            button.configuration = configuration
        } else {
            button.setTitle("跳过片头", for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            button.layer.cornerRadius = 16
            button.layer.cornerCurve = .continuous
            button.layer.masksToBounds = true
        }

        applyShadow(to: button.layer, opacity: 0.35, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func updateSkipIntroTitles(adjusting: Bool) {
        let leftTitle = adjusting ? "-\(skipIntroAdjustmentSeconds)秒" : "跳过片头"
        let rightTitle = adjusting ? "+\(skipIntroAdjustmentSeconds)秒" : "跳过片头"
        setSkipIntroTitle(leftTitle, for: leftSkipIntroButton)
        setSkipIntroTitle(rightTitle, for: rightSkipIntroButton)
    }

    private func setSkipIntroTitle(_ title: String, for button: UIButton) {
        if #available(iOS 15.0, *) {
            var configuration = button.configuration
            configuration?.title = title
            button.configuration = configuration
        } else {
            button.setTitle(title, for: .normal)
        }
    }

    private func applyIconShadow(to button: UIButton) {
        button.clipsToBounds = false
        button.imageView?.clipsToBounds = false
        button.imageView?.layer.masksToBounds = false
        applyShadow(to: button.imageView?.layer, opacity: 0.55, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func applyShadow(to layer: CALayer?,
                             opacity: Float,
                             radius: CGFloat,
                             offset: CGSize) {
        layer?.shadowColor = UIColor.black.cgColor
        layer?.shadowOpacity = opacity
        layer?.shadowRadius = radius
        layer?.shadowOffset = offset
    }

    private func setNavigationButton(_ button: UIButton, enabled: Bool) {
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.45
        button.accessibilityValue = enabled ? nil : "Unavailable"
    }

    private func configureTimeLabel(_ label: UILabel) {
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.adjustsFontForContentSizeCategory = true
        applyShadow(to: label.layer, opacity: 0.6, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func configureStatusLabel(_ label: UILabel, font: UIFont) {
        label.textColor = .white
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.82
        label.adjustsFontForContentSizeCategory = true
        applyShadow(to: label.layer, opacity: 0.62, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func configureBatteryImageView() {
        batteryImageView.contentMode = .scaleAspectFit
        batteryImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        batteryImageView.isAccessibilityElement = true
        batteryImageView.accessibilityLabel = "电量"
        applyShadow(to: batteryImageView.layer, opacity: 0.62, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func configureBatteryChargingImageView() {
        batteryChargingImageView.image = UIImage(
            systemName: "bolt.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        )
        batteryChargingImageView.tintColor = .white
        batteryChargingImageView.contentMode = .scaleAspectFit
        batteryChargingImageView.isHidden = true
        applyShadow(to: batteryChargingImageView.layer, opacity: 0.62, radius: 2, offset: CGSize(width: 0, height: 1))
    }

    private func configureWifiStatusLabel() {
        wifiStatusLabel.text = "WIFI"
        wifiStatusLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        wifiStatusLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        wifiStatusLabel.textAlignment = .center
        wifiStatusLabel.numberOfLines = 1
        wifiStatusLabel.layer.cornerRadius = 8
        wifiStatusLabel.layer.borderWidth = 1
        wifiStatusLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.58).cgColor
        wifiStatusLabel.layer.backgroundColor = UIColor.black.withAlphaComponent(0.16).cgColor
        wifiStatusLabel.layer.masksToBounds = false
        wifiStatusLabel.isAccessibilityElement = true
        wifiStatusLabel.accessibilityLabel = "无线网络"
        applyShadow(to: wifiStatusLabel.layer, opacity: 0.52, radius: 3, offset: CGSize(width: 0, height: 1))
    }

    private func startStatusUpdates() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateClockLabel()
        updateBatteryLabel()

        clockTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateClockLabel()
        }
        clockTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStatusDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStatusDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
    }

    private func updateClockLabel() {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "Hm", options: 0, locale: formatter.locale)
        clockLabel.text = formatter.string(from: Date())
    }

    private func updateBatteryLabel() {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else {
            batteryPercentLabel.text = "--%"
            batteryImageView.image = UIImage(systemName: "battery.0")
            batteryImageView.accessibilityValue = "未知"
            return
        }

        let percentage = Int((level * 100).rounded())
        batteryPercentLabel.text = "\(percentage)%"
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let symbolName: String

        if percentage <= 12 {
            symbolName = "battery.0"
        } else if percentage <= 37 {
            symbolName = "battery.25"
        } else if percentage <= 62 {
            symbolName = "battery.50"
        } else if percentage <= 87 {
            symbolName = "battery.75"
        } else {
            symbolName = "battery.100"
        }

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let symbolImage = UIImage(systemName: symbolName, withConfiguration: symbolConfiguration)
        batteryImageView.image = symbolImage
        batteryImageView.tintColor = isCharging ? UIColor.systemGreen : .white
        batteryChargingImageView.isHidden = !isCharging
        batteryImageView.accessibilityValue = isCharging ? "\(percentage)%，正在充电" : "\(percentage)%"
    }

    private func configureTitleLabel(_ label: UILabel, font: UIFont) {
        label.textColor = .white
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.78
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.55
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func configureSeekPreview() {
        seekPreviewView.alpha = 0
        seekPreviewView.isUserInteractionEnabled = false
        configurePanel(seekPreviewView, drawsBackground: true)

        seekPreviewLabel.textColor = .white
        seekPreviewLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        seekPreviewLabel.textAlignment = .center
        seekPreviewLabel.adjustsFontSizeToFitWidth = true
        seekPreviewLabel.minimumScaleFactor = 0.75
        seekPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        seekPreviewView.contentView.addSubview(seekPreviewLabel)

        NSLayoutConstraint.activate([
            seekPreviewLabel.leadingAnchor.constraint(equalTo: seekPreviewView.contentView.leadingAnchor, constant: 16),
            seekPreviewLabel.trailingAnchor.constraint(equalTo: seekPreviewView.contentView.trailingAnchor, constant: -16),
            seekPreviewLabel.topAnchor.constraint(equalTo: seekPreviewView.contentView.topAnchor, constant: 10),
            seekPreviewLabel.bottomAnchor.constraint(equalTo: seekPreviewView.contentView.bottomAnchor, constant: -10)
        ])
    }

    private func configureGestureHUD() {
        gestureHUDView.alpha = 0
        gestureHUDView.isUserInteractionEnabled = false
        configurePanel(gestureHUDView, drawsBackground: true)

        gestureHUDIconView.tintColor = .white
        gestureHUDIconView.contentMode = .scaleAspectFit
        gestureHUDIconView.translatesAutoresizingMaskIntoConstraints = false

        gestureHUDLabel.textColor = .white
        gestureHUDLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        gestureHUDLabel.textAlignment = .left
        gestureHUDLabel.adjustsFontSizeToFitWidth = true
        gestureHUDLabel.minimumScaleFactor = 0.75
        gestureHUDLabel.layer.shadowColor = UIColor.black.cgColor
        gestureHUDLabel.layer.shadowOpacity = 0.65
        gestureHUDLabel.layer.shadowRadius = 3
        gestureHUDLabel.layer.shadowOffset = CGSize(width: 0, height: 1)

        let stack = UIStackView(arrangedSubviews: [gestureHUDIconView, gestureHUDLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        gestureHUDView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            gestureHUDIconView.widthAnchor.constraint(equalToConstant: 22),
            gestureHUDIconView.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: gestureHUDView.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: gestureHUDView.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: gestureHUDView.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: gestureHUDView.contentView.bottomAnchor, constant: -12)
        ])
    }

    private func configurePausedIndicator() {
        pausedIndicatorView.alpha = 0
        pausedIndicatorView.isHidden = true
        pausedIndicatorView.isUserInteractionEnabled = false
        pausedIndicatorView.tintColor = UIColor.white.withAlphaComponent(0.9)
        pausedIndicatorView.contentMode = .scaleAspectFit
        pausedIndicatorView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 58, weight: .semibold)
        pausedIndicatorView.layer.shadowColor = UIColor.black.cgColor
        pausedIndicatorView.layer.shadowOpacity = 0.45
        pausedIndicatorView.layer.shadowRadius = 12
        pausedIndicatorView.layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    private func updatePausedIndicator(animated: Bool, allowsShowing: Bool = true) {
        pausedIndicatorHideWorkItem?.cancel()
        pausedIndicatorHideWorkItem = nil
        pausedIndicatorVisibilityGeneration += 1
        let generation = pausedIndicatorVisibilityGeneration
        let pausedIndicatorSuppressed = pausedIndicatorSuppressedUntil.map { Date() < $0 } ?? false
        if !pausedIndicatorSuppressed {
            pausedIndicatorSuppressedUntil = nil
        }
        let visible = allowsShowing &&
            isPaused &&
            !skipIntroAdjustmentActive &&
            !subtitleAdjustmentPanelVisible &&
            !pausedIndicatorSuppressed
        setPausedIndicatorVisible(visible, animated: animated, generation: generation)

        if visible {
            schedulePausedIndicatorAutoHide(generation: generation)
        }
    }

    private func schedulePausedIndicatorAutoHide(generation: Int) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.pausedIndicatorVisibilityGeneration == generation else { return }
            self.pausedIndicatorHideWorkItem = nil
            self.setPausedIndicatorVisible(false, animated: true, generation: generation)
        }
        pausedIndicatorHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausedIndicatorVisibleDuration, execute: item)
    }

    private func setPausedIndicatorVisible(_ visible: Bool, animated: Bool, generation: Int) {
        if visible {
            pausedIndicatorView.isHidden = false
        }

        let changes = {
            self.pausedIndicatorView.alpha = visible ? 1 : 0
            self.pausedIndicatorView.transform = visible ? .identity : CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.pausedIndicatorVisibilityGeneration == generation else { return }
            self.pausedIndicatorView.isHidden = !visible
        }

        if animated {
            UIView.animate(withDuration: visible ? Self.pausedIndicatorFadeInDuration : Self.pausedIndicatorFadeOutDuration,
                           delay: 0,
                           options: [.beginFromCurrentState, .curveEaseOut],
                           animations: changes,
                           completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    private func configureSubtitleAdjustmentPanel() {
        subtitleAdjustmentPanel.alpha = 0
        subtitleAdjustmentPanel.isHidden = true
        subtitleAdjustmentPanel.isUserInteractionEnabled = false
        subtitleAdjustmentPanel.layer.zPosition = 20_000
        subtitleAdjustmentPanel.transform = CGAffineTransform(translationX: 18, y: 0)
        configurePanel(subtitleAdjustmentPanel, drawsBackground: true)

        subtitleAdjustmentValueField.delegate = self
        subtitleAdjustmentValueField.keyboardType = .decimalPad
        subtitleAdjustmentValueField.returnKeyType = .done
        subtitleAdjustmentValueField.textColor = .white
        subtitleAdjustmentValueField.tintColor = .white
        subtitleAdjustmentValueField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        subtitleAdjustmentValueField.textAlignment = .center
        applyCenteredSubtitleAdjustmentValueAttributes()
        subtitleAdjustmentValueField.adjustsFontSizeToFitWidth = true
        subtitleAdjustmentValueField.minimumFontSize = 10
        subtitleAdjustmentValueField.borderStyle = .none
        subtitleAdjustmentValueField.background = nil
        subtitleAdjustmentValueField.disabledBackground = nil
        subtitleAdjustmentValueField.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        subtitleAdjustmentValueField.layer.cornerRadius = 10
        subtitleAdjustmentValueField.layer.cornerCurve = .continuous
        subtitleAdjustmentValueField.layer.masksToBounds = true
        applyShadow(to: subtitleAdjustmentValueField.layer, opacity: 0.45, radius: 4, offset: CGSize(width: 0, height: 1))
        subtitleAdjustmentValueField.accessibilityLabel = "字幕调节数值"
        subtitleAdjustmentValueField.accessibilityCustomActions = subtitleAdjustmentAccessibilityActions()
        subtitleAdjustmentValueField.addTarget(self,
                                               action: #selector(subtitleAdjustmentValueEditingDidBegin),
                                               for: .editingDidBegin)
        subtitleAdjustmentValueField.addTarget(self,
                                               action: #selector(subtitleAdjustmentValueEditingChanged),
                                               for: .editingChanged)
        subtitleAdjustmentValueField.addTarget(self,
                                               action: #selector(subtitleAdjustmentValueEditingDidEnd),
                                               for: .editingDidEnd)

        configureSubtitleAdjustmentStepButton(subtitleAdjustmentIncreaseButton,
                                              symbol: "plus",
                                              action: #selector(subtitleAdjustmentIncreaseTapped))
        configureSubtitleAdjustmentStepButton(subtitleAdjustmentDecreaseButton,
                                              symbol: "minus",
                                              action: #selector(subtitleAdjustmentDecreaseTapped))

        subtitleAdjustmentSliderContainer.translatesAutoresizingMaskIntoConstraints = false
        subtitleAdjustmentSlider.translatesAutoresizingMaskIntoConstraints = false
        subtitleAdjustmentSlider.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        subtitleAdjustmentSlider.minimumValue = 0
        subtitleAdjustmentSlider.maximumValue = 100
        subtitleAdjustmentSlider.setValue(0, animated: false)
        subtitleAdjustmentSlider.minimumTrackTintColor = .white
        subtitleAdjustmentSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        subtitleAdjustmentSlider.thumbTintColor = .white
        subtitleAdjustmentSlider.accessibilityLabel = "字幕位置"
        subtitleAdjustmentSlider.accessibilityCustomActions = subtitleAdjustmentAccessibilityActions()
        subtitleAdjustmentSlider.clipsToBounds = false
        subtitleAdjustmentSlider.layer.masksToBounds = false
        applyShadow(to: subtitleAdjustmentSlider.layer, opacity: 0.42, radius: 4, offset: CGSize(width: 0, height: 1))
        subtitleAdjustmentSlider.addTarget(self, action: #selector(subtitleAdjustmentSliderTouchDown), for: .touchDown)
        subtitleAdjustmentSlider.addTarget(self, action: #selector(subtitleAdjustmentSliderChanged), for: .valueChanged)
        subtitleAdjustmentSlider.addTarget(self,
                                           action: #selector(subtitleAdjustmentSliderTouchEnded),
                                           for: [.touchUpInside, .touchUpOutside, .touchCancel])
        subtitleAdjustmentSliderContainer.addSubview(subtitleAdjustmentSlider)

        subtitleAdjustmentIconView.tintColor = UIColor.white.withAlphaComponent(0.78)
        subtitleAdjustmentIconView.contentMode = .scaleAspectFit
        subtitleAdjustmentIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        subtitleAdjustmentIconView.isAccessibilityElement = true
        subtitleAdjustmentIconView.clipsToBounds = false
        subtitleAdjustmentIconView.layer.masksToBounds = false
        applyShadow(to: subtitleAdjustmentIconView.layer, opacity: 0.55, radius: 3, offset: CGSize(width: 0, height: 1))

        subtitleAdjustmentStack.addArrangedSubview(subtitleAdjustmentValueField)
        subtitleAdjustmentStack.addArrangedSubview(subtitleAdjustmentIncreaseButton)
        subtitleAdjustmentStack.addArrangedSubview(subtitleAdjustmentSliderContainer)
        subtitleAdjustmentStack.addArrangedSubview(subtitleAdjustmentDecreaseButton)
        subtitleAdjustmentStack.addArrangedSubview(subtitleAdjustmentIconView)
        subtitleAdjustmentStack.axis = .vertical
        subtitleAdjustmentStack.alignment = .center
        subtitleAdjustmentStack.spacing = 7
        subtitleAdjustmentStack.translatesAutoresizingMaskIntoConstraints = false
        subtitleAdjustmentPanel.contentView.addSubview(subtitleAdjustmentStack)

        NSLayoutConstraint.activate([
            subtitleAdjustmentSliderContainer.widthAnchor.constraint(equalToConstant: 44),
            subtitleAdjustmentSliderContainer.heightAnchor.constraint(equalToConstant: 126),
            subtitleAdjustmentSlider.widthAnchor.constraint(equalToConstant: 126),
            subtitleAdjustmentSlider.heightAnchor.constraint(equalToConstant: 44),
            subtitleAdjustmentSlider.centerXAnchor.constraint(equalTo: subtitleAdjustmentSliderContainer.centerXAnchor),
            subtitleAdjustmentSlider.centerYAnchor.constraint(equalTo: subtitleAdjustmentSliderContainer.centerYAnchor),
            subtitleAdjustmentValueField.widthAnchor.constraint(equalToConstant: 54),
            subtitleAdjustmentValueField.heightAnchor.constraint(equalToConstant: 30),
            subtitleAdjustmentIncreaseButton.widthAnchor.constraint(equalToConstant: 30),
            subtitleAdjustmentIncreaseButton.heightAnchor.constraint(equalToConstant: 26),
            subtitleAdjustmentDecreaseButton.widthAnchor.constraint(equalToConstant: 30),
            subtitleAdjustmentDecreaseButton.heightAnchor.constraint(equalToConstant: 26),
            subtitleAdjustmentIconView.widthAnchor.constraint(equalToConstant: 28),
            subtitleAdjustmentIconView.heightAnchor.constraint(equalToConstant: 24),
            subtitleAdjustmentStack.leadingAnchor.constraint(equalTo: subtitleAdjustmentPanel.contentView.leadingAnchor, constant: 9),
            subtitleAdjustmentStack.trailingAnchor.constraint(equalTo: subtitleAdjustmentPanel.contentView.trailingAnchor, constant: -9),
            subtitleAdjustmentStack.centerYAnchor.constraint(equalTo: subtitleAdjustmentPanel.contentView.centerYAnchor)
        ])

        updateSubtitleAdjustmentModeButtons()
        updateSubtitleAdjustmentValueDisplays(forceField: true)
    }

    private func configureSubtitleAdjustmentStepButton(_ button: UIButton,
                                                       symbol: String,
                                                       action: Selector) {
        button.tintColor = .white
        button.setImage(UIImage(systemName: symbol,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
                        for: .normal)
        button.backgroundColor = .clear
        button.adjustsImageSizeForAccessibilityContentSizeCategory = true
        button.imageView?.contentMode = .scaleAspectFit
        button.clipsToBounds = false
        button.imageView?.clipsToBounds = false
        button.imageView?.layer.masksToBounds = false
        applyShadow(to: button.imageView?.layer, opacity: 0.55, radius: 3, offset: CGSize(width: 0, height: 1))
        button.addTarget(self, action: action, for: .touchDown)
    }

    private func applyCenteredSubtitleAdjustmentValueAttributes() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: subtitleAdjustmentValueField.font ?? UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: subtitleAdjustmentValueField.textColor ?? UIColor.white,
        ]
        subtitleAdjustmentValueField.defaultTextAttributes = attributes
        subtitleAdjustmentValueField.typingAttributes = attributes
    }

    private func setSubtitleAdjustmentMode(_ mode: SubtitleAdjustmentMode) {
        guard subtitleAdjustmentMode != mode else { return }
        subtitleAdjustmentValueField.resignFirstResponder()
        subtitleAdjustmentMode = mode
        updateSubtitleAdjustmentModeAppearance()
        updateSubtitleAdjustmentSlider(animated: true)
        updateSubtitleAdjustmentValueDisplays(forceField: true)
    }

    private func updateSubtitleAdjustmentModeButtons() {
        updateSubtitleAdjustmentModeAppearance()
    }

    private func updateSubtitleAdjustmentModeAppearance() {
        updateSubtitleAdjustmentValueFieldPlacement()
        updateSubtitleAdjustmentIcon()
        updateSubtitleAdjustmentStepButtonAccessibility()
    }

    private func updateSubtitleAdjustmentValueFieldPlacement() {
        let targetIndex = 0
        guard let currentIndex = subtitleAdjustmentStack.arrangedSubviews.firstIndex(of: subtitleAdjustmentValueField),
              currentIndex != targetIndex
        else { return }

        subtitleAdjustmentStack.removeArrangedSubview(subtitleAdjustmentValueField)
        subtitleAdjustmentValueField.removeFromSuperview()
        subtitleAdjustmentStack.insertArrangedSubview(subtitleAdjustmentValueField, at: targetIndex)
    }

    private func updateSubtitleAdjustmentIcon() {
        let imageName: String
        let accessibilityLabel: String
        switch subtitleAdjustmentMode {
        case .position:
            imageName = "arrow.up.and.down"
            accessibilityLabel = "字幕位置"
        case .scale:
            imageName = "textformat.size"
            accessibilityLabel = "字幕大小"
        case .border:
            imageName = "lineweight"
            accessibilityLabel = "字幕轮廓宽度"
        case .delay:
            imageName = "timer"
            accessibilityLabel = "字幕延迟"
        }
        subtitleAdjustmentIconView.image = UIImage(systemName: imageName)
        subtitleAdjustmentIconView.accessibilityLabel = accessibilityLabel
    }

    private func updateSubtitleAdjustmentStepButtonAccessibility() {
        let label: String
        switch subtitleAdjustmentMode {
        case .position:
            label = "字幕位置"
        case .scale:
            label = "字幕大小"
        case .border:
            label = "字幕轮廓宽度"
        case .delay:
            label = "字幕延迟"
        }
        subtitleAdjustmentIncreaseButton.accessibilityLabel = "增加\(label)"
        subtitleAdjustmentDecreaseButton.accessibilityLabel = "减少\(label)"
    }

    private func updateSubtitleAdjustmentSlider(animated: Bool) {
        let value: Double
        switch subtitleAdjustmentMode {
        case .position:
            subtitleAdjustmentSlider.minimumValue = 0
            subtitleAdjustmentSlider.maximumValue = 100
            subtitleAdjustmentSlider.accessibilityLabel = "字幕位置"
            value = Self.subtitlePositionOffset(from: subtitlePosition)
        case .scale:
            subtitleAdjustmentSlider.minimumValue = 0.5
            subtitleAdjustmentSlider.maximumValue = 2.5
            subtitleAdjustmentSlider.accessibilityLabel = "字幕大小"
            value = subtitleScale
        case .border:
            subtitleAdjustmentSlider.minimumValue = 0
            subtitleAdjustmentSlider.maximumValue = 8
            subtitleAdjustmentSlider.accessibilityLabel = "字幕轮廓宽度"
            value = subtitleBorderSize
        case .delay:
            subtitleAdjustmentSlider.minimumValue = Float(min(-10, subtitleDelay))
            subtitleAdjustmentSlider.maximumValue = Float(max(10, subtitleDelay))
            subtitleAdjustmentSlider.accessibilityLabel = "字幕延迟"
            value = subtitleDelay
        }

        subtitleAdjustmentSlider.setValue(Float(value), animated: animated)
    }

    private func applySubtitleAdjustmentSliderValue() {
        let sliderValue = Double(subtitleAdjustmentSlider.value)
        switch subtitleAdjustmentMode {
        case .position:
            subtitlePosition = Self.subtitlePosition(fromOffset: sliderValue)
            onSubtitlePositionChanged?(subtitlePosition)
        case .scale:
            subtitleScale = sliderValue
            onSubtitleScaleChanged?(subtitleScale)
        case .border:
            subtitleBorderSize = Self.clampedSubtitleBorderSize(sliderValue)
            onSubtitleBorderSizeChanged?(subtitleBorderSize)
        case .delay:
            subtitleDelay = sliderValue
            onSubtitleDelayChanged?(subtitleDelay)
        }
        updateSubtitleAdjustmentValueDisplays(forceField: true)
    }

    private func applySubtitleAdjustmentInputValue(commit: Bool) {
        let normalizedText = (subtitleAdjustmentValueField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalizedText.isEmpty, let rawValue = Double(normalizedText) else {
            if commit {
                updateSubtitleAdjustmentValueDisplays(forceField: true)
            }
            return
        }

        switch subtitleAdjustmentMode {
        case .position:
            subtitlePosition = Self.subtitlePosition(fromOffset: rawValue)
            onSubtitlePositionChanged?(subtitlePosition)
        case .scale:
            subtitleScale = min(max(rawValue, 0.5), 2.5)
            onSubtitleScaleChanged?(subtitleScale)
        case .border:
            subtitleBorderSize = Self.clampedSubtitleBorderSize(rawValue)
            onSubtitleBorderSizeChanged?(subtitleBorderSize)
        case .delay:
            subtitleDelay = rawValue
            onSubtitleDelayChanged?(subtitleDelay)
        }

        updateSubtitleAdjustmentSlider(animated: false)
        updateSubtitleAdjustmentValueDisplays(forceField: commit)
    }

    private func stepSubtitleAdjustment(direction: Int) {
        if subtitleAdjustmentValueField.isFirstResponder {
            subtitleAdjustmentValueField.resignFirstResponder()
        }

        switch subtitleAdjustmentMode {
        case .position:
            let offset = Self.subtitlePositionOffset(from: subtitlePosition) + Double(direction) * Self.subtitlePositionStep
            subtitlePosition = Self.subtitlePosition(fromOffset: offset)
            onSubtitlePositionChanged?(subtitlePosition)
        case .scale:
            let steppedValue = subtitleScale + Double(direction) * Self.subtitleScaleStep
            subtitleScale = min(max((steppedValue * 100).rounded() / 100, 0.5), 2.5)
            onSubtitleScaleChanged?(subtitleScale)
        case .border:
            let steppedValue = subtitleBorderSize + Double(direction) * Self.subtitleBorderSizeStep
            subtitleBorderSize = Self.clampedSubtitleBorderSize((steppedValue * 10).rounded() / 10)
            onSubtitleBorderSizeChanged?(subtitleBorderSize)
        case .delay:
            let steppedValue = subtitleDelay + Double(direction) * Self.subtitleDelayStep
            subtitleDelay = (steppedValue * 10).rounded() / 10
            onSubtitleDelayChanged?(subtitleDelay)
        }

        updateSubtitleAdjustmentSlider(animated: false)
        updateSubtitleAdjustmentValueDisplays(forceField: true)
    }

    private func updateSubtitleAdjustmentValueDisplays(forceField: Bool) {
        let keyboardType: UIKeyboardType = subtitleAdjustmentMode == .delay ? .numbersAndPunctuation : .decimalPad
        if subtitleAdjustmentValueField.keyboardType != keyboardType {
            subtitleAdjustmentValueField.keyboardType = keyboardType
            if subtitleAdjustmentValueField.isFirstResponder {
                subtitleAdjustmentValueField.reloadInputViews()
            }
        }

        switch subtitleAdjustmentMode {
        case .position:
            subtitleAdjustmentValueField.placeholder = "0-100"
            subtitleAdjustmentValueField.accessibilityValue = Self.formatSubtitlePosition(subtitlePosition)
        case .scale:
            subtitleAdjustmentValueField.placeholder = "0.5-2.5"
            subtitleAdjustmentValueField.accessibilityValue = "\(Self.formatSubtitleScale(subtitleScale))x"
        case .border:
            subtitleAdjustmentValueField.placeholder = "0-8"
            subtitleAdjustmentValueField.accessibilityValue = Self.formatSubtitleBorderSize(subtitleBorderSize)
        case .delay:
            subtitleAdjustmentValueField.placeholder = "±10s"
            subtitleAdjustmentValueField.accessibilityValue = Self.formatSubtitleDelay(subtitleDelay)
        }

        guard forceField || !subtitleAdjustmentValueField.isFirstResponder else { return }

        switch subtitleAdjustmentMode {
        case .position:
            subtitleAdjustmentValueField.text = Self.formatSubtitlePosition(subtitlePosition)
        case .scale:
            subtitleAdjustmentValueField.text = Self.formatSubtitleScale(subtitleScale)
        case .border:
            subtitleAdjustmentValueField.text = Self.formatSubtitleBorderSize(subtitleBorderSize)
        case .delay:
            subtitleAdjustmentValueField.text = Self.formatSubtitleDelayInput(subtitleDelay)
        }
    }

    private static func formatSubtitlePosition(_ value: Double) -> String {
        String(format: "%.0f", subtitlePositionOffset(from: value).rounded())
    }

    private static func subtitlePositionOffset(from position: Double) -> Double {
        min(max(subtitlePositionBaseline - min(max(position, 0), 100), 0), 100)
    }

    private static func subtitlePosition(fromOffset offset: Double) -> Double {
        subtitlePositionBaseline - min(max(offset, 0), 100)
    }

    private static func formatSubtitleScale(_ value: Double) -> String {
        let roundedValue = min(max(value, 0.5), 2.5)
        var text = String(format: "%.2f", roundedValue)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private static func formatSubtitleBorderSize(_ value: Double) -> String {
        let roundedValue = clampedSubtitleBorderSize(value)
        var text = String(format: "%.1f", roundedValue)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private static func clampedSubtitleBorderSize(_ value: Double) -> Double {
        min(max(value, 0), 8)
    }

    private static func formatSubtitleDelay(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "0s"
        }
        return String(format: "%+.1fs", value)
    }

    private static func formatSubtitleDelayInput(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "0"
        }
        var text = String(format: "%.1f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private func configureRenderedSubtitleLabel() {
        renderedSubtitleLabel.alpha = 0
        renderedSubtitleLabel.isUserInteractionEnabled = false
        renderedSubtitleLabel.backgroundColor = .clear
        renderedSubtitleLabel.textAlignment = .center
        renderedSubtitleLabel.numberOfLines = 0
        renderedSubtitleLabel.lineBreakMode = .byWordWrapping
        renderedSubtitleLabel.adjustsFontSizeToFitWidth = true
        renderedSubtitleLabel.minimumScaleFactor = 0.72
        renderedSubtitleLabel.layer.shadowColor = UIColor.black.cgColor
        renderedSubtitleLabel.layer.shadowOpacity = 0.95
        renderedSubtitleLabel.layer.shadowRadius = 4
        renderedSubtitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        renderedSubtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func configurePanel(_ panel: UIVisualEffectView, drawsBackground: Bool) {
        if #available(iOS 26.0, *), !drawsBackground {
            panel.effect = nil
            panel.backgroundColor = .clear
            panel.layer.borderWidth = 0
            return
        }

        panel.clipsToBounds = true
        panel.layer.cornerRadius = 28
        panel.layer.cornerCurve = .continuous
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        panel.layer.borderWidth = 0.5
    }

    private static func panelEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .clear)
            effect.isInteractive = true
            effect.tintColor = UIColor.black.withAlphaComponent(0.18)
            return effect
        }

        return UIBlurEffect(style: .systemUltraThinMaterialDark)
    }

    private func setButtonImage(_ button: UIButton, symbol: String) {
        let symbolConfiguration = button === playPauseButton ? Self.playButtonSymbolConfiguration : Self.bottomButtonSymbolConfiguration
        if #available(iOS 15.0, *), var configuration = button.configuration {
            configuration.image = Self.systemImage(named: symbol, configuration: symbolConfiguration)
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            button.configuration = configuration
        } else {
            button.setImage(Self.systemImage(named: symbol, configuration: symbolConfiguration), for: .normal)
        }
    }

    private func setJumpButtonImage(_ button: UIButton, interval: MediaJumpInterval, direction: JumpDirection) {
        let symbolConfiguration = Self.jumpButtonSymbolConfiguration
        let image: UIImage?
        if interval.usesNativeNumberedSystemImage || interval.iconText == nil {
            image = Self.systemImage(
                named: direction.systemImage(for: interval),
                configuration: symbolConfiguration
            )
        } else if let iconText = interval.iconText {
            image = Self.jumpIconImage(systemName: direction.baseSystemImage, text: iconText)
        } else {
            image = Self.systemImage(
                named: direction.baseSystemImage,
                configuration: symbolConfiguration
            )
        }

        if #available(iOS 15.0, *), var configuration = button.configuration {
            configuration.image = image
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            button.configuration = configuration
        } else {
            button.setImage(image, for: .normal)
        }
    }

    private static func systemImage(named name: String, configuration: UIImage.SymbolConfiguration?) -> UIImage? {
        if let configuration {
            return UIImage(systemName: name, withConfiguration: configuration)
        }
        return UIImage(systemName: name)
    }

    private static func jumpIconImage(systemName: String, text: String) -> UIImage? {
        let size = CGSize(width: 25, height: 24.7)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        guard let symbolImage = UIImage(systemName: systemName, withConfiguration: symbolConfiguration) else {
            return UIImage(systemName: systemName)
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let symbolSize = symbolImage.size
            let symbolRect = CGRect(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbolImage
                .withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: symbolRect)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let fontSize: CGFloat = text.count == 1 ? 12.0 : 11.4
            let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle,
            ]
            let textSize = text.size(withAttributes: attributes)
            let horizontalScale: CGFloat = text.count == 1 ? 0.74 : 0.75
            let textRect = CGRect(
                x: -size.width * (1 - horizontalScale) / (2 * horizontalScale),
                y: (size.height - textSize.height) / 2 + 0.5,
                width: size.width / horizontalScale,
                height: textSize.height
            )
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.translateBy(x: size.width / 2, y: 0)
            context?.scaleBy(x: horizontalScale, y: 1)
            context?.translateBy(x: -size.width / 2, y: 0)
            text.draw(in: textRect, withAttributes: attributes)
            context?.restoreGState()
        }
        .withRenderingMode(.alwaysTemplate)
    }

    private func configureTracksMenu() {
        tracksButton.showsMenuAsPrimaryAction = true
        tracksButton.addTarget(self, action: #selector(menuButtonTouched), for: .touchDown)
        if #available(iOS 16.0, *) {
            tracksButton.preferredMenuElementOrder = .fixed
        }
        updateSubtitleMenu()
    }

    private func configureOpenMenu() {
        openButton.showsMenuAsPrimaryAction = true
        openButton.addTarget(self, action: #selector(menuButtonTouched), for: .touchDown)
        if #available(iOS 16.0, *) {
            openButton.preferredMenuElementOrder = .fixed
        }
        updateOpenMenu()
    }

    private func configureSpeedMenu() {
        speedButton.showsMenuAsPrimaryAction = true
        speedButton.addTarget(self, action: #selector(menuButtonTouched), for: .touchDown)
        if #available(iOS 16.0, *) {
            speedButton.preferredMenuElementOrder = .fixed
        }
        updateSpeedMenu()
    }

    private func configureSettingsMenu() {
        settingsButton.showsMenuAsPrimaryAction = true
        settingsButton.addTarget(self, action: #selector(menuButtonTouched), for: .touchDown)
        if #available(iOS 16.0, *) {
            settingsButton.preferredMenuElementOrder = .fixed
        }
        updateSettingsMenu()
    }

    private func updateSpeedMenu() {
        let speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
        let actions = speeds.map { speed in
            let action = UIAction(
                title: Self.formatSpeed(speed),
                image: UIImage(systemName: "speedometer")
            ) { [weak self] _ in
                self?.currentPlaybackSpeed = speed
                self?.speedButton.accessibilityValue = Self.formatSpeed(speed)
                self?.updateSpeedMenu()
                self?.onPlaybackSpeedSelected?(speed)
                self?.onMenuSelectionFinished?()
            }
            action.state = abs(speed - currentPlaybackSpeed) < 0.001 ? .on : .off
            return action
        }
        speedButton.menu = UIMenu(title: "播放速度", options: .displayInline, children: actions)
    }

    private func updateSettingsMenu() {
        let position = UIAction(title: "调整字幕位置",
                                image: UIImage(systemName: "arrow.up.and.down")) { [weak self] _ in
            self?.openSubtitleAdjustmentFromSettings(.position)
        }
        let scale = UIAction(title: "调整字幕大小",
                             image: UIImage(systemName: "textformat.size")) { [weak self] _ in
            self?.openSubtitleAdjustmentFromSettings(.scale)
        }
        let border = UIAction(title: "调整字幕轮廓",
                              image: UIImage(systemName: "lineweight")) { [weak self] _ in
            self?.openSubtitleAdjustmentFromSettings(.border)
        }
        let delay = UIAction(title: "调整字幕延迟",
                             image: UIImage(systemName: "timer")) { [weak self] _ in
            self?.openSubtitleAdjustmentFromSettings(.delay)
        }

        if subtitleAdjustmentPanelVisible {
            switch subtitleAdjustmentMode {
            case .position:
                position.state = .on
            case .scale:
                scale.state = .on
            case .border:
                border.state = .on
            case .delay:
                delay.state = .on
            }
        }

        let subtitleSettings = UIMenu(title: "字幕设置",
                                      image: UIImage(systemName: "captions.bubble"),
                                      children: [
            position,
            scale,
            border,
            delay,
        ])
        settingsButton.menu = UIMenu(title: "设置", children: [
            subtitleSettings,
        ])
        updateSettingsAccessibilityActions()
    }

    private func openSubtitleAdjustmentFromSettings(_ mode: SubtitleAdjustmentMode) {
        onMenuOpened?()
        DispatchQueue.main.async { [weak self] in
            self?.showSubtitleAdjustmentPanel(mode: mode, animated: true)
        }
    }

    private func updateSettingsAccessibilityActions() {
        settingsButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "调整字幕位置",
                target: self,
                selector: #selector(accessibilityAdjustSubtitlePosition)
            ),
            UIAccessibilityCustomAction(
                name: "调整字幕大小",
                target: self,
                selector: #selector(accessibilityAdjustSubtitleScale)
            ),
            UIAccessibilityCustomAction(
                name: "调整字幕轮廓",
                target: self,
                selector: #selector(accessibilityAdjustSubtitleBorder)
            ),
            UIAccessibilityCustomAction(
                name: "调整字幕延迟",
                target: self,
                selector: #selector(accessibilityAdjustSubtitleDelay)
            ),
        ]
    }

    private func subtitleAdjustmentAccessibilityActions() -> [UIAccessibilityCustomAction] {
        [
            UIAccessibilityCustomAction(
                name: "关闭字幕调整",
                target: self,
                selector: #selector(accessibilityCloseSubtitleAdjustment)
            ),
            UIAccessibilityCustomAction(
                name: "关闭播放器",
                target: self,
                selector: #selector(accessibilityClosePlayer)
            ),
        ]
    }

    private func updateOpenMenu() {
        let openFile = UIAction(title: "打开文件...",
                                image: UIImage(systemName: "doc")) { [weak self] _ in
            self?.onMenuSelectionFinished?()
            self?.onOpen?()
        }

        let openFolder = UIAction(title: "打开文件夹...",
                                  image: UIImage(systemName: "folder"),
                                  attributes: onOpenFolder == nil ? .disabled : []) { [weak self] _ in
            self?.onMenuSelectionFinished?()
            self?.onOpenFolder?()
        }

        openButton.menu = UIMenu(title: "打开", options: .displayInline, children: [openFile, openFolder])
    }

    private func updateSubtitleMenu() {
        var actions: [UIMenuElement] = []

        if subtitleTracks.isEmpty {
            let empty = UIAction(title: "无字幕轨道",
                                 image: UIImage(systemName: "text.badge.xmark"),
                                 attributes: .disabled) { _ in }
            actions.append(empty)
        } else {
            actions.append(contentsOf: subtitleTracks.map { track in
                let action = UIAction(
                    title: Self.localizedSubtitleTrackTitle(track.title),
                    image: UIImage(systemName: "captions.bubble")
                ) { [weak self] _ in
                    self?.onSelectSubtitleTrack?(track.id)
                    self?.onMenuSelectionFinished?()
                }
                action.state = track.isSelected || track.id == selectedSubtitleID ? .on : .off
                return action
            })
        }

        let openSubtitle = UIAction(title: "打开字幕文件...",
                                    image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            self?.onMenuSelectionFinished?()
            self?.onOpenSubtitle?()
        }
        actions.append(openSubtitle)

        let off = UIAction(title: "关闭字幕",
                           image: UIImage(systemName: "captions.bubble")) { [weak self] _ in
            self?.onDisableSubtitle?()
            self?.onMenuSelectionFinished?()
        }
        off.state = selectedSubtitleID == nil ? .on : .off
        actions.append(off)

        tracksButton.menu = UIMenu(title: "字幕", options: .displayInline, children: actions)
    }

    private static func localizedSubtitleTrackTitle(_ title: String) -> String {
        let parts = title
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(\.isNotEmpty)

        guard parts.isNotEmpty else { return title }

        return parts
            .map(localizedSubtitleTrackPart)
            .joined(separator: " · ")
    }

    private static func localizedSubtitleTrackPart(_ part: String) -> String {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return part }

        let normalized = trimmed
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        switch normalized {
        case "external":
            return "外部"
        case "external-subtitle", "external-subtitles":
            return "外部字幕"
        case "subtitle", "subtitles":
            return "字幕"
        case "forced":
            return "强制"
        case "default":
            return "默认"
        case "selected":
            return "已选择"
        case "text-subtitle", "text-subtitles":
            return "文本字幕"
        case "eng", "en", "english":
            return "英语"
        case "jpn", "jp", "ja", "japanese":
            return "日语"
        case "kor", "ko", "korean":
            return "韩语"
        case "chi", "zho", "zh", "chinese":
            return "中文"
        case "chs", "sc", "zh-cn", "zh-hans", "simplified-chinese", "chinese-simplified":
            return "简体中文"
        case "cht", "tc", "zh-tw", "zh-hant", "traditional-chinese", "chinese-traditional":
            return "繁体中文"
        case "cantonese", "yue":
            return "粤语"
        case "mandarin", "cmn":
            return "普通话"
        case "und", "unknown":
            return "未知"
        case "cc":
            return "隐藏字幕"
        case "sdh":
            return "听障字幕"
        default:
            if normalized.hasPrefix("subtitle-") {
                let suffix = String(normalized.dropFirst("subtitle-".count))
                if suffix.isNotEmpty, suffix.allSatisfy(\.isNumber) {
                    return "字幕 \(suffix)"
                }
            }
            return subtitleTrackPartByReplacingKnownEnglish(in: trimmed)
        }
    }

    private static func subtitleTrackPartByReplacingKnownEnglish(in part: String) -> String {
        var localized = part
        let replacements = [
            ("External Subtitle", "外部字幕"),
            ("Text Subtitle", "文本字幕"),
            ("Subtitle", "字幕"),
            ("External", "外部"),
            ("Forced", "强制"),
            ("Default", "默认"),
            ("Selected", "已选择"),
            ("Simplified Chinese", "简体中文"),
            ("Traditional Chinese", "繁体中文"),
            ("Chinese", "中文"),
            ("English", "英语"),
            ("Japanese", "日语"),
            ("Korean", "韩语"),
        ]

        for (source, target) in replacements {
            localized = localized.replacingOccurrences(of: source, with: target, options: .caseInsensitive)
        }

        return localized
    }

    #if DEBUG
    static func localizedSubtitleTrackTitleForSmoke(_ title: String) -> String {
        localizedSubtitleTrackTitle(title)
    }

    var subtitleMenuTitlesForSmoke: [String] {
        Self.menuTitlesForSmoke(tracksButton.menu)
    }

    var settingsMenuTitlesForSmoke: [String] {
        Self.menuTitlesForSmoke(settingsButton.menu)
    }

    var settingsMenuRootChildTitlesForSmoke: [String] {
        settingsButton.menu?.children.map(\.title) ?? []
    }

    private static func menuTitlesForSmoke(_ menu: UIMenu?) -> [String] {
        guard let menu else { return [] }
        return menuTitlesForSmoke(menu)
    }

    private static func menuTitlesForSmoke(_ menu: UIMenu) -> [String] {
        var titles = menu.title.isEmpty ? [] : [menu.title]
        for child in menu.children {
            if let submenu = child as? UIMenu {
                titles.append(contentsOf: menuTitlesForSmoke(submenu))
            } else if !child.title.isEmpty {
                titles.append(child.title)
            }
        }
        return titles
    }

    var transportControlLabelsForSmoke: [String] {
        [
            previousEpisodeButton,
            seekBackwardButton,
            playPauseButton,
            seekForwardButton,
            nextEpisodeButton,
            tracksButton,
            speedButton,
            episodeListButton,
        ].compactMap(\.accessibilityLabel)
    }

    #endif

    @objc private func playPauseTapped() {
        onPlayPause?()
    }

    @objc private func previousEpisodeTapped() {
        onPreviousEpisode?()
    }

    @objc private func seekBackwardTapped() {
        onSeekBackward?()
    }

    @objc private func seekForwardTapped() {
        onSeekForward?()
    }

    @objc private func skipIntroTapped() {
        guard !skipIntroAdjustmentActive else { return }
        skipIntroButtonsDismissed = true
        UIView.animate(withDuration: 0.16, animations: {
            self.skipIntroStack.alpha = 0
        }, completion: { [weak self] _ in
            self?.skipIntroStack.isHidden = true
            self?.skipIntroStack.isUserInteractionEnabled = false
        })
        onSkipIntro?(Double(skipIntroSeconds))
        onSkipIntroAdjustmentCommitted?(skipIntroSeconds)
    }

    @objc private func skipIntroLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            skipIntroAdjustmentCommitWorkItem?.cancel()
            let direction = gesture.view === leftSkipIntroButton ? -1.0 : 1.0
            beginSkipIntroAdjustmentIfNeeded()

            let delta: Int
            let jumpDirection: Double
            if skipIntroAdjustmentHasJumpedDefault {
                delta = 5
                skipIntroAdjustmentSeconds = max(5, skipIntroAdjustmentSeconds + Int(direction) * delta)
                jumpDirection = direction
            } else {
                delta = skipIntroAdjustmentSeconds
                skipIntroAdjustmentHasJumpedDefault = true
                jumpDirection = 1
            }

            skipIntroAdjustmentShouldResumePlayback = !isPaused
            onSkipIntroReverseBegan?()
            updateSkipIntroTitles(adjusting: true)
            showSkipIntroButtonsForAdjustment()
            onMenuOpened?()
            onSkipIntro?(jumpDirection * Double(delta))
            startSkipIntroAdjustmentRepeat(direction: direction)

        case .ended, .cancelled, .failed:
            stopSkipIntroAdjustmentRepeat()
            if skipIntroAdjustmentShouldResumePlayback {
                onSkipIntroReverseEnded?()
            }
            skipIntroAdjustmentShouldResumePlayback = false
            scheduleSkipIntroAdjustmentCommit()

        default:
            break
        }
    }

    private func beginSkipIntroAdjustmentIfNeeded() {
        guard !skipIntroAdjustmentActive else { return }
        skipIntroAdjustmentActive = true
        skipIntroAdjustmentHasJumpedDefault = false
        skipIntroAdjustmentSeconds = skipIntroSeconds
        skipIntroButtonsDismissed = false
        skipIntroStack.isHidden = false
        skipIntroStack.isUserInteractionEnabled = true
    }

    private func showSkipIntroButtonsForAdjustment() {
        skipIntroStack.isHidden = false
        skipIntroStack.isUserInteractionEnabled = true
        skipIntroButtonsDismissed = false
        UIView.animate(withDuration: 0.15) {
            self.skipIntroStack.alpha = 1
        }
    }

    private func scheduleSkipIntroAdjustmentCommit() {
        skipIntroAdjustmentCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitSkipIntroAdjustment()
        }
        skipIntroAdjustmentCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func startSkipIntroAdjustmentRepeat(direction: Double) {
        stopSkipIntroAdjustmentRepeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.repeatSkipIntroAdjustment(direction: direction)
        }
        RunLoop.main.add(timer, forMode: .common)
        skipIntroAdjustmentRepeatTimer = timer
    }

    private func stopSkipIntroAdjustmentRepeat() {
        skipIntroAdjustmentRepeatTimer?.invalidate()
        skipIntroAdjustmentRepeatTimer = nil
    }

    private func repeatSkipIntroAdjustment(direction: Double) {
        guard skipIntroAdjustmentActive else {
            stopSkipIntroAdjustmentRepeat()
            return
        }

        let delta = 1
        skipIntroAdjustmentSeconds = max(5, skipIntroAdjustmentSeconds + Int(direction) * delta)
        updateSkipIntroTitles(adjusting: true)
        onSkipIntro?(direction * Double(delta))
    }

    private func commitSkipIntroAdjustment() {
        guard skipIntroAdjustmentActive else { return }
        stopSkipIntroAdjustmentRepeat()
        skipIntroAdjustmentActive = false
        skipIntroAdjustmentHasJumpedDefault = false
        skipIntroSeconds = skipIntroAdjustmentSeconds
        skipIntroButtonsDismissed = true
        onSkipIntroAdjustmentCommitted?(skipIntroAdjustmentSeconds)
        UIView.animate(withDuration: 0.2, animations: {
            self.skipIntroStack.alpha = 0
        }, completion: { [weak self] _ in
            self?.skipIntroStack.isHidden = true
            self?.skipIntroStack.isUserInteractionEnabled = false
            self?.updateSkipIntroTitles(adjusting: false)
        })
    }

    private func cancelSkipIntroAdjustment() {
        stopSkipIntroAdjustmentRepeat()
        skipIntroAdjustmentCommitWorkItem?.cancel()
        skipIntroAdjustmentCommitWorkItem = nil
        skipIntroAdjustmentActive = false
        skipIntroAdjustmentHasJumpedDefault = false
        skipIntroAdjustmentShouldResumePlayback = false
        skipIntroAdjustmentSeconds = skipIntroSeconds
        updateSkipIntroTitles(adjusting: false)
    }

    @objc private func nextEpisodeTapped() {
        onNextEpisode?()
    }

    @objc private func episodeListTapped() {
        onEpisodeList?()
    }

    @objc private func menuButtonTouched() {
        onMenuOpened?()
    }

    @objc private func batteryStatusDidChange() {
        updateBatteryLabel()
    }

    @objc private func accessibilityAdjustSubtitlePosition() -> Bool {
        showSubtitleAdjustmentPanel(mode: .position, animated: true)
        return true
    }

    @objc private func accessibilityAdjustSubtitleScale() -> Bool {
        showSubtitleAdjustmentPanel(mode: .scale, animated: true)
        return true
    }

    @objc private func accessibilityAdjustSubtitleBorder() -> Bool {
        showSubtitleAdjustmentPanel(mode: .border, animated: true)
        return true
    }

    @objc private func accessibilityAdjustSubtitleDelay() -> Bool {
        showSubtitleAdjustmentPanel(mode: .delay, animated: true)
        return true
    }

    @objc private func accessibilityCloseSubtitleAdjustment() -> Bool {
        setSubtitleAdjustmentPanelVisible(false, animated: true)
        return true
    }

    @objc private func accessibilityClosePlayer() -> Bool {
        onClose?()
        return true
    }

    @objc private func subtitleAdjustmentSliderTouchDown() {
        onSubtitleAdjustmentBegan?()
    }

    @objc private func subtitleAdjustmentSliderChanged() {
        applySubtitleAdjustmentSliderValue()
    }

    @objc private func subtitleAdjustmentSliderTouchEnded() {
        onSubtitleAdjustmentEnded?()
    }

    @objc private func subtitleAdjustmentIncreaseTapped() {
        stepSubtitleAdjustment(direction: 1)
    }

    @objc private func subtitleAdjustmentDecreaseTapped() {
        stepSubtitleAdjustment(direction: -1)
    }

    @objc private func subtitleAdjustmentValueEditingDidBegin() {
        subtitleAdjustmentValueField.setNeedsLayout()
        subtitleAdjustmentValueField.layoutIfNeeded()
        onSubtitleAdjustmentBegan?()
    }

    @objc private func subtitleAdjustmentValueEditingChanged() {
        applySubtitleAdjustmentInputValue(commit: false)
    }

    @objc private func subtitleAdjustmentValueEditingDidEnd() {
        applySubtitleAdjustmentInputValue(commit: true)
        onSubtitleAdjustmentEnded?()
    }

    @objc private func subtitleAdjustmentValueDoneTapped() {
        subtitleAdjustmentValueField.resignFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        guard textField === subtitleAdjustmentValueField else { return true }
        guard !string.isEmpty else { return true }

        let allowedCharacters = CharacterSet(charactersIn: subtitleAdjustmentMode == .delay ? "0123456789.,+-" : "0123456789.,")
        guard string.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return false
        }

        let current = textField.text ?? ""
        guard let textRange = Range(range, in: current) else { return false }
        let next = current.replacingCharacters(in: textRange, with: string)
        let separatorCount = next.filter { $0 == "." || $0 == "," }.count
        if separatorCount > 1 { return false }
        let signCount = next.filter { $0 == "-" || $0 == "+" }.count
        if signCount > 1 { return false }
        if let signIndex = next.firstIndex(where: { $0 == "-" || $0 == "+" }),
           signIndex != next.startIndex {
            return false
        }

        switch subtitleAdjustmentMode {
        case .position:
            return signCount == 0 && separatorCount == 0
        case .scale:
            return signCount == 0
        case .border:
            return signCount == 0
        case .delay:
            return true
        }
    }

    @objc private func sliderTouchDown() {
        trackingSlider = true
        setSeekPreview(time: Double(slider.value), duration: mediaDuration, visible: false)
        onSeekBegan?()
    }

    @objc private func sliderValueChanged() {
        onSeekChanged?(Double(slider.value))
    }

    @objc private func sliderTouchEnded() {
        trackingSlider = false
        setSeekPreview(time: Double(slider.value), duration: mediaDuration, visible: false)
        onSeekEnded?(Double(slider.value))
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

    private static func formatDuration(_ duration: Duration) -> String {
        let seconds = max(1, Int(duration.seconds.rounded()))
        return "\(seconds) Seconds"
    }

    private static func formatNetworkSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite && bytesPerSecond > 0 else { return "0 KB/s" }
        let kib = bytesPerSecond / 1024
        if kib < 1024 {
            return String(format: "%.0f KB/s", kib)
        }
        return String(format: "%.1f MB/s", kib / 1024)
    }

    private static func formatTime(_ seconds: Double) -> String {
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
}
