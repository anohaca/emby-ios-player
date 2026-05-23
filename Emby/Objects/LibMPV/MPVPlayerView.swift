import Metal
import QuartzCore
import UIKit

final class MPVPlayerView: UIView {
    private let renderLayer = CAMetalLayer()

    var onReadyForRendering: ((MPVPlayerView) -> Void)? {
        didSet {
            notifyIfReadyForRendering()
        }
    }

    var metalLayer: CAMetalLayer {
        renderLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderLayer.frame = bounds
        updateDrawableSize()
        CATransaction.commit()

        notifyIfReadyForRendering()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawableSize()
        notifyIfReadyForRendering()
    }

    func refreshRenderingSurfaceForForeground() {
        setNeedsLayout()
        layoutIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderLayer.isHidden = false
        renderLayer.opacity = 1
        updateDrawableSize()
        CATransaction.commit()
        notifyIfReadyForRendering()
    }

    private func configureLayer() {
        backgroundColor = .black
        isOpaque = true
        layer.masksToBounds = true

        renderLayer.device = MTLCreateSystemDefaultDevice()
        renderLayer.isOpaque = true
        renderLayer.pixelFormat = .bgra8Unorm
        renderLayer.framebufferOnly = false
        renderLayer.presentsWithTransaction = false
        renderLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
        renderLayer.frame = bounds
        if renderLayer.superlayer == nil {
            layer.addSublayer(renderLayer)
        }
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
    }

    private func notifyIfReadyForRendering() {
        guard window != nil,
              bounds.width > 1,
              bounds.height > 1,
              metalLayer.device != nil
        else { return }

        onReadyForRendering?(self)
    }
}
