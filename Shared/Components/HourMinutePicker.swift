//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct HourMinutePicker: View {

    @State
    private var isPresented = false

    private let title: String
    private let interval: Binding<TimeInterval>

    init(_ title: String, interval: Binding<TimeInterval>) {
        self.title = title
        self.interval = interval
    }

    @ViewBuilder
    var body: some View {
        ChevronButton(
            title,
            subtitle: Text(Duration.seconds(interval.wrappedValue), format: .hourMinuteAbbreviated)
        ) {
            isPresented.toggle()
        }

        if isPresented {
            _HourMinutePickerView(interval: interval)
        }
    }
}

// MARK: - iOS Picker

#if os(iOS)

private struct _HourMinutePickerView: UIViewRepresentable {

    let interval: Binding<TimeInterval>

    func makeUIView(context: Context) -> some UIView {
        let picker = UIDatePicker(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerMode = .countDownTimer
        picker.countDownDuration = interval.wrappedValue

        context.coordinator.add(picker: picker)
        context.coordinator.interval = interval

        return picker
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {

        var interval: Binding<TimeInterval>!

        func add(picker: UIDatePicker) {
            picker.addTarget(
                self,
                action: #selector(
                    dateChanged
                ),
                for: .valueChanged
            )
        }

        @objc
        func dateChanged(_ picker: UIDatePicker) {
            interval.wrappedValue = picker.countDownDuration
        }
    }
}

#endif
