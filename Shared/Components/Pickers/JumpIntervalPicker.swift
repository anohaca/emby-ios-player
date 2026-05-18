//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

// TODO: Generic StorablePicker?
// - Combine JumpIntervalPicker & PlaybackSpeedPicker if possible

struct JumpIntervalPicker: View {

    @State
    private var customSeconds: Int = 0
    @State
    private var isPresentingCustomInterval = false

    private let title: String
    private let selection: Binding<MediaJumpInterval>

    init(_ title: String, selection: Binding<MediaJumpInterval>) {
        self.title = title
        self.selection = selection
    }

    @ViewBuilder
    private var picker: some View {
        if #available(iOS 18.0, tvOS 18.0, *) {
            Picker(
                title,
                selection: selection
                    .map(
                        getter: {
                            if case .custom = $0 { .zero } else { $0.rawValue }
                        },
                        setter: {
                            MediaJumpInterval(rawValue: $0)
                        }
                    )
            ) {
                ForEach(MediaJumpInterval.allCases, id: \.hashValue) { interval in
                    Text(interval.rawValue, format: .minuteSecondsNarrow)
                        .tag(interval.rawValue)
                }

                Divider()

                Text(L10n.custom)
                    .tag(Duration.zero)
            } currentValueLabel: {
                Text(selection.wrappedValue.rawValue, format: .minuteSecondsNarrow)
            }
        } else {
            Picker(
                title,
                selection: selection
                    .map(
                        getter: {
                            if case .custom = $0 { .zero } else { $0.rawValue }
                        },
                        setter: {
                            MediaJumpInterval(rawValue: $0)
                        }
                    )
            ) {
                ForEach(MediaJumpInterval.allCases, id: \.hashValue) { interval in
                    Text(interval.rawValue, format: .minuteSecondsNarrow)
                        .tag(interval.rawValue)
                }

                Divider()

                Text(L10n.custom)
                    .tag(Duration.zero)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        ListRowMenu(title, subtitle: Text(selection.wrappedValue.rawValue, format: .minuteSecondsNarrow)) {
            picker
        }
        #else
        picker
        #endif
    }

    var body: some View {
        content
            .backport
            .onChange(of: selection.wrappedValue) { oldValue, newValue in
                if case let .custom(interval) = newValue {
                    if interval == .zero {
                        customSeconds = Int(oldValue.rawValue.seconds)
                        selection.wrappedValue = .init(rawValue: .seconds(customSeconds))
                        isPresentingCustomInterval = true
                    } else {
                        if let matchingStatic = MediaJumpInterval.allCases.first(where: { $0.rawValue == interval }) {
                            selection.wrappedValue = matchingStatic
                        }
                    }
                }
            }
            .customJumpIntervalAlert(
                isPresented: $isPresentingCustomInterval,
                customSeconds: $customSeconds,
                selection: selection
            )
    }
}

private extension View {

    @ViewBuilder
    func customJumpIntervalAlert(
        isPresented: Binding<Bool>,
        customSeconds: Binding<Int>,
        selection: Binding<MediaJumpInterval>
    ) -> some View {
        #if os(iOS)
        background(
            AlertTextFieldPresenter(
                title: L10n.jump,
                message: L10n.customJumpIntervalDescription,
                placeholder: L10n.duration,
                text: "\(customSeconds.wrappedValue)",
                keyboardType: .numberPad,
                isPresented: isPresented
            ) { text in
                let seconds = clamp(Int(text) ?? customSeconds.wrappedValue, min: 1, max: 600)
                customSeconds.wrappedValue = seconds
                selection.wrappedValue = .custom(interval: Duration.seconds(seconds))
            }
        )
        #else
        alert(L10n.jump, isPresented: isPresented) {
            TextField(L10n.duration, value: customSeconds.clamp(min: 1, max: 600), format: .number)
                .keyboardType(.numberPad)

            Button(L10n.ok) {
                selection.wrappedValue = .custom(interval: Duration.seconds(customSeconds.wrappedValue))
            }
        } message: {
            Text(L10n.customJumpIntervalDescription)
        }
        #endif
    }
}

#if os(iOS)
struct AlertTextFieldPresenter: UIViewControllerRepresentable {

    let title: String
    let message: String
    let placeholder: String
    let text: String
    let keyboardType: UIKeyboardType
    @Binding
    var isPresented: Bool

    let onCommit: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.configuration = self

        if isPresented {
            guard context.coordinator.alert == nil else { return }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.text = text
                textField.keyboardType = keyboardType
                textField.addTarget(
                    context.coordinator,
                    action: #selector(Coordinator.textDidChange(_:)),
                    for: .editingChanged
                )
                context.coordinator.currentText = text
                AlertTextFieldChrome.apply(to: textField)
            }
            alert.addAction(UIAlertAction(title: L10n.ok, style: .default) { _ in
                context.coordinator.commit()
            })

            context.coordinator.alert = alert
            DispatchQueue.main.async {
                guard viewController.presentedViewController == nil else { return }
                viewController.present(alert, animated: true)
            }
        } else if let alert = context.coordinator.alert {
            context.coordinator.alert = nil
            alert.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {

        var alert: UIAlertController?
        var configuration: AlertTextFieldPresenter?
        var currentText = ""

        @objc
        func textDidChange(_ textField: UITextField) {
            currentText = textField.text ?? ""
            AlertTextFieldChrome.apply(to: textField)
        }

        func commit() {
            guard let configuration else { return }
            configuration.onCommit(currentText)
            self.configuration?.isPresented = false
            alert = nil
        }

    }
}

private enum AlertTextFieldChrome {

    static func apply(to textField: UITextField) {
        applyOnce(to: textField)

        DispatchQueue.main.async { [weak textField] in
            guard let textField else { return }
            applyOnce(to: textField)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textField] in
            guard let textField else { return }
            applyOnce(to: textField)
        }
    }

    private static func applyOnce(to textField: UITextField) {
        let inputBackgroundColor = UIColor(
            red: 48 / 255,
            green: 48 / 255,
            blue: 55 / 255,
            alpha: 1
        )
        textField.backgroundColor = inputBackgroundColor
        textField.layer.backgroundColor = inputBackgroundColor.cgColor
        textField.isOpaque = false

        textField.subviews.forEach { subview in
            clearRectangularInputBackgrounds(
                in: subview,
                root: textField,
                inputBackgroundColor: inputBackgroundColor
            )
        }
    }

    private static func clearRectangularInputBackgrounds(
        in view: UIView,
        root: UIView,
        inputBackgroundColor: UIColor
    ) {
        let frame = view.convert(view.bounds, to: root)
        let preservesSystemFieldShape =
            abs(frame.minX) <= 2 &&
            abs(frame.minY) <= 2 &&
            abs(frame.width - root.bounds.width) <= 4 &&
            abs(frame.height - root.bounds.height) <= 4

        if !preservesSystemFieldShape {
            view.backgroundColor = .clear
            view.layer.backgroundColor = UIColor.clear.cgColor
        } else {
            view.backgroundColor = inputBackgroundColor
            view.layer.backgroundColor = inputBackgroundColor.cgColor
        }

        view.isOpaque = false
        view.subviews.forEach { subview in
            clearRectangularInputBackgrounds(
                in: subview,
                root: root,
                inputBackgroundColor: inputBackgroundColor
            )
        }
    }
}
#endif
