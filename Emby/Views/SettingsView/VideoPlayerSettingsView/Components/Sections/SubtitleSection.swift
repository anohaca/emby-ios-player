//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftUI
import UIKit

extension VideoPlayerSettingsView {
    struct SubtitleSection: View {
        @Default(.VideoPlayer.Subtitle.subtitleFontName)
        private var subtitleFontName
        @Default(.VideoPlayer.Subtitle.subtitleSize)
        private var subtitleSize
        @Default(.VideoPlayer.Subtitle.subtitleColor)
        private var subtitleColor
        @Default(.VideoPlayer.Subtitle.subtitleBorderSize)
        private var subtitleBorderSize
        @Default(.VideoPlayer.Subtitle.subtitleDelay)
        private var subtitleDelay

        @Router
        private var router

        var body: some View {
            Section {
                ChevronButton(L10n.subtitleFont, subtitle: subtitleFontName) {
                    router.route(to: .fontPicker(selection: $subtitleFontName))
                }

                Stepper(value: $subtitleSize, step: 1) {
                    LabeledContent(L10n.subtitleSize) {
                        ClearSettingsIntegerField(value: $subtitleSize)
                    }
                }

                ColorPicker(L10n.subtitleColor, selection: $subtitleColor, supportsOpacity: false)

                Stepper(value: $subtitleBorderSize, step: 0.5) {
                    LabeledContent("字幕轮廓") {
                        ClearSettingsDoubleField(value: $subtitleBorderSize, keyboardType: .decimalPad)
                    }
                }

                Stepper(value: $subtitleDelay, step: 0.1) {
                    LabeledContent("字幕延迟") {
                        ClearSettingsDoubleField(value: $subtitleDelay, keyboardType: .numbersAndPunctuation)
                    }
                }
            } header: {
                Text(L10n.subtitle)
            } footer: {
                Text(L10n.subtitlesDisclaimer)
            }
        }
    }
}

struct ClearSettingsIntegerField: UIViewRepresentable {
    @Binding var value: Int

    func makeUIView(context: Context) -> UITextField {
        let textField = ClearSettingsTextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.textAlignment = .right
        textField.textColor = .label
        textField.tintColor = .systemPurple
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.required, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.value = $value
        if !textField.isFirstResponder {
            textField.text = String(value)
        }
        textField.clearEditingBackgrounds()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Int>

        init(value: Binding<Int>) {
            self.value = value
        }

        @objc
        func editingChanged(_ textField: UITextField) {
            guard let text = textField.text, let parsed = Int(text) else { return }
            value.wrappedValue = parsed
            textField.clearEditingBackgrounds()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if let text = textField.text, let parsed = Int(text) {
                value.wrappedValue = parsed
            }
            textField.text = String(value.wrappedValue)
            textField.clearEditingBackgrounds()
        }
    }
}

private struct ClearSettingsDoubleField: UIViewRepresentable {
    @Binding var value: Double
    let keyboardType: UIKeyboardType

    func makeUIView(context: Context) -> UITextField {
        let textField = ClearSettingsTextField()
        textField.delegate = context.coordinator
        textField.keyboardType = keyboardType
        textField.textAlignment = .right
        textField.textColor = .label
        textField.tintColor = .systemPurple
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.required, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.value = $value
        if !textField.isFirstResponder {
            textField.text = Self.format(value)
        }
        textField.clearEditingBackgrounds()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc
        func editingChanged(_ textField: UITextField) {
            guard let text = textField.text, let parsed = Double(text) else { return }
            value.wrappedValue = parsed
            textField.clearEditingBackgrounds()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if let text = textField.text, let parsed = Double(text) {
                value.wrappedValue = parsed
            }
            textField.text = ClearSettingsDoubleField.format(value.wrappedValue)
            textField.clearEditingBackgrounds()
        }
    }
}

private final class ClearSettingsTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 72, height: super.intrinsicContentSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clearEditingBackgrounds()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        clearEditingBackgrounds()
        return result
    }
}

private extension UIView {
    func clearEditingBackgrounds() {
        backgroundColor = .clear
        layer.backgroundColor = UIColor.clear.cgColor
        for subview in subviews {
            subview.clearEditingBackgrounds()
        }
    }
}
