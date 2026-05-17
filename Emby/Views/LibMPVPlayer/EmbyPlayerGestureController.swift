import UIKit

final class PlayerGestureController: NSObject {
    enum VerticalAdjustmentSide {
        case brightness
        case volume
    }

    var onToggleControls: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onSeekBy: ((Double) -> Void)?
    var onSeekGestureChanged: ((Double, UIGestureRecognizer.State) -> Void)?
    var onLongPressSpeedChanged: ((UIGestureRecognizer.State) -> Void)?
    var onVerticalAdjustmentChanged: ((VerticalAdjustmentSide, Double, UIGestureRecognizer.State) -> Void)?

    private weak var view: UIView?
    private var panMode = PanMode.undecided
    private var panStartLocation = CGPoint.zero
    private let panDecisionThreshold: CGFloat = 10

    init(view: UIView) {
        self.view = view
        super.init()
        installGestures()
    }

    private enum PanMode {
        case undecided
        case horizontalSeek
        case verticalAdjustment(VerticalAdjustmentSide)
    }

    private func installGestures() {
        guard let view else { return }

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2

        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 18
        longPress.delegate = self

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self

        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pan)
    }

    @objc private func singleTapped() {
        onToggleControls?()
    }

    @objc private func doubleTapped() {
        onTogglePlayback?()
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .ended, .cancelled, .failed:
            onLongPressSpeedChanged?(gesture.state)
        default:
            break
        }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }

        let translation = gesture.translation(in: view)
        let seconds = Double(translation.x / max(view.bounds.width, 1)) * 60.0
        let verticalDelta = Double(-translation.y / max(view.bounds.height, 1))

        switch gesture.state {
        case .began:
            panMode = .undecided
            panStartLocation = gesture.location(in: view)
        case .changed:
            if case .undecided = panMode {
                decidePanMode(translation: translation)
            }

            switch panMode {
            case .undecided:
                break
            case .horizontalSeek:
                onSeekGestureChanged?(seconds, gesture.state)
            case .verticalAdjustment(let side):
                onVerticalAdjustmentChanged?(side, verticalDelta, gesture.state)
            }
        case .ended:
            switch panMode {
            case .undecided:
                break
            case .horizontalSeek:
                onSeekGestureChanged?(seconds, gesture.state)
                if abs(seconds) >= 1 {
                    onSeekBy?(seconds)
                }
            case .verticalAdjustment(let side):
                onVerticalAdjustmentChanged?(side, verticalDelta, gesture.state)
            }
            panMode = .undecided
        case .cancelled, .failed:
            switch panMode {
            case .undecided:
                break
            case .horizontalSeek:
                onSeekGestureChanged?(seconds, gesture.state)
            case .verticalAdjustment(let side):
                onVerticalAdjustmentChanged?(side, verticalDelta, gesture.state)
            }
            panMode = .undecided
        default:
            break
        }
    }

    private func decidePanMode(translation: CGPoint) {
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)
        guard max(horizontal, vertical) >= panDecisionThreshold else { return }

        if horizontal >= vertical {
            panMode = .horizontalSeek
            onSeekGestureChanged?(0, .began)
            return
        }

        let side: VerticalAdjustmentSide = panStartLocation.x < (view?.bounds.midX ?? 0) ? .brightness : .volume
        panMode = .verticalAdjustment(side)
        onVerticalAdjustmentChanged?(side, 0, .began)
    }
}

extension PlayerGestureController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let controlsView = view as? PlayerControlsView,
           controlsView.shouldSuppressPlayerGesture(at: touch.location(in: controlsView)) {
            return false
        }

        var currentView = touch.view
        while let view = currentView {
            if view is UIControl {
                return false
            }
            currentView = view.superview
        }
        return true
    }
}
