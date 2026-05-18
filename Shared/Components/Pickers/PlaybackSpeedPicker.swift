//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: Generic StorablePicker?
// - Combine PlaybackSpeedPicker & JumpIntervalPicker if possible

struct PlaybackSpeedPicker: View {

    @State
    private var customSpeed: Float = 1.0
    @State
    private var isPresentingCustomSpeed = false

    private let title: String
    private let selection: Binding<PlaybackSpeed>

    init(_ title: String, selection: Binding<PlaybackSpeed>) {
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
                        getter: { value -> Float in
                            if case .custom = value { Float(0) } else { value.rawValue }
                        },
                        setter: {
                            PlaybackSpeed(rawValue: $0)
                        }
                    )
            ) {
                ForEach(PlaybackSpeed.allCases, id: \.hashValue) { speed in
                    Text(speed.displayTitle)
                        .tag(speed.rawValue)
                }

                Divider()

                Text(L10n.custom)
                    .tag(Float(0))
            } currentValueLabel: {
                Text(selection.wrappedValue.displayTitle)
            }
        } else {
            Picker(
                title,
                selection: selection
                    .map(
                        getter: { value -> Float in
                            if case .custom = value { Float(0) } else { value.rawValue }
                        },
                        setter: {
                            PlaybackSpeed(rawValue: $0)
                        }
                    )
            ) {
                ForEach(PlaybackSpeed.allCases, id: \.hashValue) { speed in
                    Text(speed.displayTitle)
                        .tag(speed.rawValue)
                }

                Divider()

                Text(L10n.custom)
                    .tag(Float(0))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        ListRowMenu(title, subtitle: Text(selection.wrappedValue.displayTitle)) {
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
                if case let .custom(value) = newValue {
                    if value == .zero {
                        customSpeed = oldValue.rawValue
                        isPresentingCustomSpeed = true
                    } else {
                        if let matchingStatic = PlaybackSpeed.allCases.first(where: { $0.rawValue == value }) {
                            selection.wrappedValue = matchingStatic
                        }
                    }
                }
            }
            .customPlaybackSpeedAlert(
                isPresented: $isPresentingCustomSpeed,
                customSpeed: $customSpeed,
                selection: selection
            )
    }
}

private extension View {

    @ViewBuilder
    func customPlaybackSpeedAlert(
        isPresented: Binding<Bool>,
        customSpeed: Binding<Float>,
        selection: Binding<PlaybackSpeed>
    ) -> some View {
        #if os(iOS)
        background(
            AlertTextFieldPresenter(
                title: L10n.playbackSpeed,
                message: L10n.customPlaybackSpeedDescription,
                placeholder: L10n.playbackSpeed,
                text: "\(customSpeed.wrappedValue)",
                keyboardType: .decimalPad,
                isPresented: isPresented
            ) { text in
                let normalizedText = text.replacingOccurrences(of: ",", with: ".")
                let speed = clamp(Float(normalizedText) ?? customSpeed.wrappedValue, min: 0.1, max: 10.0)
                customSpeed.wrappedValue = speed
                selection.wrappedValue = .custom(speed)
            }
        )
        #else
        alert(L10n.playbackSpeed, isPresented: isPresented) {
            TextField(L10n.playbackSpeed, value: customSpeed.clamp(min: 0.1, max: 10.0), format: .number)
                .keyboardType(.decimalPad)

            Button(L10n.ok) {
                selection.wrappedValue = .custom(customSpeed.wrappedValue)
            }
        } message: {
            Text(L10n.customPlaybackSpeedDescription)
        }
        #endif
    }
}
