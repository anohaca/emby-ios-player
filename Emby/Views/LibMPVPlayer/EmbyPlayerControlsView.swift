import UIKit

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
    }

    private static let pausedIndicatorVisibleDuration: TimeInterval = 0.5
    private static let pausedIndicatorFadeOutDuration: TimeInterval = 0.5
    private static let pausedIndicatorFadeInDuration: TimeInterval = 0.18
    private static let forwardJumpButtonSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    private static let subtitlePositionBaseline = 100.0
    private static let subtitlePositionStep = 1.0
    private static let subtitleScaleStep = 0.01
    private static let subtitleBorderSizeStep = 0.1

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
    var onNextEpisode: (() -> Void)?
    var onPlaybackSpeedSelected: ((Double) -> Void)?
    var onMenuOpened: (() -> Void)?
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
    var onSubtitleAdjustmentBegan: (() -> Void)?
    var onSubtitleAdjustmentEnded: (() -> Void)?
    var onSubtitleAdjustmentVisibilityChanged: ((Bool) -> Void)?

    private let topBar = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let bottomBar = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let openButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let previousEpisodeButton = UIButton(type: .system)
    private let seekBackwardButton = UIButton(type: .system)
    private let seekForwardButton = UIButton(type: .system)
    private let nextEpisodeButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let tracksButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()
    private let seekPreviewView = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let seekPreviewLabel = UILabel()
    private let gestureHUDView = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let gestureHUDIconView = UIImageView()
    private let gestureHUDLabel = UILabel()
    private let pausedIndicatorView = UIImageView(image: UIImage(systemName: "pause.fill"))
    private let renderedSubtitleLabel = UILabel()
    private let subtitleAdjustmentPanel = UIVisualEffectView(effect: PlayerControlsView.panelEffect())
    private let subtitleAdjustmentValueField = UITextField()
    private let subtitleAdjustmentIncreaseButton = UIButton(type: .system)
    private let subtitleAdjustmentSliderContainer = UIView()
    private let subtitleAdjustmentSlider = UISlider()
    private let subtitleAdjustmentDecreaseButton = UIButton(type: .system)
    private let subtitleAdjustmentIconView = UIImageView()
    private let subtitleAdjustmentStack = UIStackView()

    private var trackingSlider = false
    private var previewingTimeline = false
    private var mediaDuration = 0.0
    private var currentPlaybackSpeed = 1.0
    private var isPaused = false
    private var areControlsHidden = false
    private var pausedIndicatorHideWorkItem: DispatchWorkItem?
    private var pausedIndicatorVisibilityGeneration = 0
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
    private var gestureHUDCenterYConstraint: NSLayoutConstraint?
    private var gestureHUDTopConstraint: NSLayoutConstraint?
    private var subtitleVisibleBottomConstraint: NSLayoutConstraint?
    private var subtitleControlsBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        let symbol = paused ? "play.fill" : "pause.fill"
        setButtonImage(playPauseButton, symbol: symbol)
        playPauseButton.accessibilityLabel = paused ? "Play" : "Pause"
        updatePausedIndicator(animated: true)
    }

    func update(time: Double, duration: Double) {
        mediaDuration = duration
        guard !trackingSlider && !previewingTimeline else { return }
        updateTimeline(time: time, duration: duration)
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
    }

    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        controlsVisibilityGeneration += 1
        let generation = controlsVisibilityGeneration
        areControlsHidden = hidden
        if !hidden {
            topBar.isHidden = false
            bottomBar.isHidden = false
            topBar.isUserInteractionEnabled = true
            bottomBar.isUserInteractionEnabled = true
        }

        let changes = {
            self.topBar.alpha = hidden ? 0 : 1
            self.bottomBar.alpha = hidden ? 0 : 1
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.controlsVisibilityGeneration == generation else { return }
            self.topBar.isHidden = hidden
            self.bottomBar.isHidden = hidden
            self.topBar.isUserInteractionEnabled = !hidden
            self.bottomBar.isUserInteractionEnabled = !hidden
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

    func updateSubtitleAdjustment(position: Double, scale: Double, borderSize: Double? = nil) {
        let nextPosition = min(max(position, 0), 100)
        let nextScale = min(max(scale, 0.5), 2.5)
        let nextBorderSize = borderSize.map(Self.clampedSubtitleBorderSize) ?? subtitleBorderSize
        guard subtitlePosition != nextPosition ||
            subtitleScale != nextScale ||
            subtitleBorderSize != nextBorderSize
        else { return }

        subtitlePosition = nextPosition
        subtitleScale = nextScale
        if borderSize != nil {
            subtitleBorderSize = nextBorderSize
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

    func updateEpisodeNavigation(canGoPrevious: Bool, canGoNext: Bool) {
        setNavigationButton(previousEpisodeButton, enabled: canGoPrevious)
        setNavigationButton(nextEpisodeButton, enabled: canGoNext)
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
        configureButton(previousEpisodeButton, symbol: "backward.end.fill", label: "上一集")
        configureButton(seekBackwardButton, symbol: "gobackward.10", label: "后退 10 秒")
        configureButton(playPauseButton, symbol: "play.fill", label: "播放")
        configureButton(
            seekForwardButton,
            symbol: "goforward.10",
            label: "前进 10 秒",
            symbolConfiguration: Self.forwardJumpButtonSymbolConfiguration
        )
        configureButton(nextEpisodeButton, symbol: "forward.end.fill", label: "下一集")
        configureButton(speedButton, symbol: "speedometer", label: "播放速度")
        configureButton(tracksButton, symbol: "captions.bubble", label: "字幕")
        configureButton(settingsButton, symbol: "gearshape", label: "设置")
        applyIconShadow(to: settingsButton)
        configureTitleLabel(titleLabel, font: .systemFont(ofSize: 16, weight: .semibold))
        configureTitleLabel(subtitleLabel, font: .systemFont(ofSize: 12, weight: .medium))
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.isHidden = true

        previousEpisodeButton.addTarget(self, action: #selector(previousEpisodeTapped), for: .touchUpInside)
        seekBackwardButton.addTarget(self, action: #selector(seekBackwardTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        seekForwardButton.addTarget(self, action: #selector(seekForwardTapped), for: .touchUpInside)
        nextEpisodeButton.addTarget(self, action: #selector(nextEpisodeTapped), for: .touchUpInside)
        configureOpenMenu()
        configureSpeedMenu()
        configureTracksMenu()
        configureSettingsMenu()
        updateEpisodeNavigation(canGoPrevious: false, canGoNext: false)

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
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        slider.thumbTintColor = .white
        applyShadow(to: slider.layer, opacity: 0.45, radius: 3, offset: CGSize(width: 0, height: 1))
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

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
        topBar.contentView.addSubview(topStack)

        let transportStack = UIStackView(arrangedSubviews: [
            previousEpisodeButton,
            seekBackwardButton,
            playPauseButton,
            seekForwardButton,
            nextEpisodeButton,
            tracksButton,
            speedButton
        ])
        transportStack.axis = .horizontal
        transportStack.alignment = .center
        transportStack.distribution = .equalSpacing
        transportStack.spacing = 10
        transportStack.translatesAutoresizingMaskIntoConstraints = false

        let timelineStack = UIStackView(arrangedSubviews: [currentTimeLabel, slider, durationLabel])
        timelineStack.axis = .horizontal
        timelineStack.alignment = .center
        timelineStack.spacing = 10
        timelineStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomStack = UIStackView(arrangedSubviews: [timelineStack, transportStack])
        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
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
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 10),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -10),
            topStack.topAnchor.constraint(equalTo: topBar.contentView.topAnchor, constant: 8),
            topStack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -8),
            titleStack.centerXAnchor.constraint(equalTo: topBar.contentView.centerXAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: openButton.trailingAnchor, constant: 16),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -16),

            bottomBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            bottomBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -12),
            bottomStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            bottomStack.bottomAnchor.constraint(equalTo: bottomBar.contentView.bottomAnchor, constant: -4),
            transportStack.centerXAnchor.constraint(equalTo: bottomStack.centerXAnchor),
            timelineStack.heightAnchor.constraint(equalToConstant: 30),

            playPauseButton.widthAnchor.constraint(equalToConstant: 50),
            playPauseButton.heightAnchor.constraint(equalToConstant: 50),
            previousEpisodeButton.widthAnchor.constraint(equalToConstant: 42),
            previousEpisodeButton.heightAnchor.constraint(equalToConstant: 42),
            seekBackwardButton.widthAnchor.constraint(equalToConstant: 42),
            seekBackwardButton.heightAnchor.constraint(equalToConstant: 42),
            seekForwardButton.widthAnchor.constraint(equalToConstant: 42),
            seekForwardButton.heightAnchor.constraint(equalToConstant: 42),
            nextEpisodeButton.widthAnchor.constraint(equalToConstant: 42),
            nextEpisodeButton.heightAnchor.constraint(equalToConstant: 42),
            speedButton.widthAnchor.constraint(equalToConstant: 42),
            speedButton.heightAnchor.constraint(equalToConstant: 42),
            openButton.widthAnchor.constraint(equalToConstant: 46),
            openButton.heightAnchor.constraint(equalToConstant: 46),
            tracksButton.widthAnchor.constraint(equalToConstant: 46),
            tracksButton.heightAnchor.constraint(equalToConstant: 46),
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
        let visible = allowsShowing && isPaused && !subtitleAdjustmentPanelVisible
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
        subtitleAdjustmentValueField.adjustsFontSizeToFitWidth = true
        subtitleAdjustmentValueField.minimumFontSize = 10
        subtitleAdjustmentValueField.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        subtitleAdjustmentValueField.layer.cornerRadius = 10
        subtitleAdjustmentValueField.layer.cornerCurve = .continuous
        subtitleAdjustmentValueField.layer.masksToBounds = false
        applyShadow(to: subtitleAdjustmentValueField.layer, opacity: 0.45, radius: 4, offset: CGSize(width: 0, height: 1))
        subtitleAdjustmentValueField.inputAccessoryView = makeSubtitleAdjustmentInputAccessoryView()
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

    private func makeSubtitleAdjustmentInputAccessoryView() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done,
                            target: self,
                            action: #selector(subtitleAdjustmentValueDoneTapped))
        ]
        return toolbar
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
        }

        updateSubtitleAdjustmentSlider(animated: false)
        updateSubtitleAdjustmentValueDisplays(forceField: true)
    }

    private func updateSubtitleAdjustmentValueDisplays(forceField: Bool) {
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
        }

        guard forceField || !subtitleAdjustmentValueField.isFirstResponder else { return }

        switch subtitleAdjustmentMode {
        case .position:
            subtitleAdjustmentValueField.text = Self.formatSubtitlePosition(subtitlePosition)
        case .scale:
            subtitleAdjustmentValueField.text = Self.formatSubtitleScale(subtitleScale)
        case .border:
            subtitleAdjustmentValueField.text = Self.formatSubtitleBorderSize(subtitleBorderSize)
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
        if #available(iOS 15.0, *), var configuration = button.configuration {
            configuration.image = UIImage(systemName: symbol)
            button.configuration = configuration
        } else {
            button.setImage(UIImage(systemName: symbol), for: .normal)
        }
    }

    private func setJumpButtonImage(_ button: UIButton, interval: MediaJumpInterval, direction: JumpDirection) {
        let symbolConfiguration = direction == .forward ? Self.forwardJumpButtonSymbolConfiguration : nil
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

        if subtitleAdjustmentPanelVisible {
            switch subtitleAdjustmentMode {
            case .position:
                position.state = .on
            case .scale:
                scale.state = .on
            case .border:
                border.state = .on
            }
        }

        let subtitleSettings = UIMenu(title: "字幕设置",
                                      image: UIImage(systemName: "captions.bubble"),
                                      children: [
            position,
            scale,
            border,
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
            self?.onOpen?()
        }

        let openFolder = UIAction(title: "打开文件夹...",
                                  image: UIImage(systemName: "folder"),
                                  attributes: onOpenFolder == nil ? .disabled : []) { [weak self] _ in
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
                }
                action.state = track.isSelected || track.id == selectedSubtitleID ? .on : .off
                return action
            })
        }

        let openSubtitle = UIAction(title: "打开字幕文件...",
                                    image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            self?.onOpenSubtitle?()
        }
        actions.append(openSubtitle)

        let off = UIAction(title: "关闭字幕",
                           image: UIImage(systemName: "captions.bubble")) { [weak self] _ in
            self?.onDisableSubtitle?()
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

    @objc private func nextEpisodeTapped() {
        onNextEpisode?()
    }

    @objc private func menuButtonTouched() {
        onMenuOpened?()
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

        let allowedCharacters = CharacterSet(charactersIn: "0123456789.,")
        guard string.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return false
        }

        let current = textField.text ?? ""
        guard let textRange = Range(range, in: current) else { return false }
        let next = current.replacingCharacters(in: textRange, with: string)
        let separatorCount = next.filter { $0 == "." || $0 == "," }.count
        if separatorCount > 1 { return false }

        switch subtitleAdjustmentMode {
        case .position:
            return separatorCount == 0 && next.count <= 3
        case .scale:
            return next.count <= 4
        case .border:
            return next.count <= 3
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
