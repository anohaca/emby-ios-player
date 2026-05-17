import UIKit

extension PlayerControlsView {
    func applyEmbyPlaybackChrome() {
        configureOpenButtonAsClose()

        #if DEBUG
        if #available(iOS 26.0, *) {
            NSLog("EmbyPlayerChrome liquid-glass=enabled api=iOS26")
        }
        #endif
    }

    private func configureOpenButtonAsClose() {
        guard let button = firstButton(accessibilityLabel: "打开")
            ?? firstButton(accessibilityLabel: "Open")
            ?? firstButton(accessibilityLabel: "关闭")
            ?? firstButton(accessibilityLabel: "Close")
        else {
            return
        }

        button.accessibilityLabel = "关闭"
        button.showsMenuAsPrimaryAction = false
        button.menu = nil
        button.removeTarget(nil, action: nil, for: .allEvents)
        button.addTarget(self, action: #selector(embyCloseTapped), for: .touchUpInside)

        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.clearGlass()
            configuration.image = UIImage(systemName: "xmark")
            configuration.baseForegroundColor = .white
            configuration.buttonSize = .large
            configuration.cornerStyle = .capsule
            button.configuration = configuration
        } else {
            button.setImage(UIImage(systemName: "xmark"), for: .normal)
        }

        applyCloseIconShadow(to: button)
    }

    @objc private func embyCloseTapped() {
        (onClose ?? onOpen)?()
    }

    private func applyCloseIconShadow(to button: UIButton) {
        button.clipsToBounds = false
        button.imageView?.clipsToBounds = false
        button.imageView?.layer.masksToBounds = false
        button.imageView?.layer.shadowColor = UIColor.black.cgColor
        button.imageView?.layer.shadowOpacity = 0.55
        button.imageView?.layer.shadowRadius = 3
        button.imageView?.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func firstButton(accessibilityLabel: String) -> UIButton? {
        allSubviews(of: self, matching: UIButton.self)
            .first { $0.accessibilityLabel == accessibilityLabel }
    }

    private func allSubviews<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
        var matches: [T] = []
        for subview in view.subviews {
            if let match = subview as? T {
                matches.append(match)
            }
            matches.append(contentsOf: allSubviews(of: subview, matching: type))
        }
        return matches
    }
}
