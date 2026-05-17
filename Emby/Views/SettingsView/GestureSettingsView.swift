//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct GestureSettingsView: View {

    @Default(.VideoPlayer.Gesture.longPressSpeedMultiplier)
    private var longPressSpeedMultiplier

    var body: some View {
        Form {

            Section(L10n.longPress) {
                Picker(L10n.playbackSpeed, selection: $longPressSpeedMultiplier) {
                    ForEach(Self.longPressMultipliers, id: \.self) { speed in
                        Text(speed.displayTitle)
                            .tag(speed)
                    }
                }
            }

            Section {
                Picker(L10n.horizontalPan, selection: .constant(PanGestureAction.scrub)) {
                    ForEach(PanGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.horizontalSwipe, selection: .constant(SwipeGestureAction.none)) {
                    ForEach(SwipeGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.longPress, selection: .constant(LongPressGestureAction.playbackSpeed)) {
                    ForEach(LongPressGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.multiTap, selection: .constant(MultiTapGestureAction.none)) {
                    ForEach(MultiTapGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.doubleTouch, selection: .constant(DoubleTouchGestureAction.pausePlay)) {
                    ForEach(DoubleTouchGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.pinch, selection: .constant(PinchGestureAction.none)) {
                    ForEach(PinchGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.leftVerticalPan, selection: .constant(PanGestureAction.brightness)) {
                    ForEach(PanGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }

                Picker(L10n.rightVerticalPan, selection: .constant(PanGestureAction.volume)) {
                    ForEach(PanGestureAction.allCases, id: \.self) { action in
                        Text(action.displayTitle)
                            .tag(action)
                    }
                }
            }
            .disabled(true)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            longPressSpeedMultiplier = Self.normalizedLongPressMultiplier(longPressSpeedMultiplier)
        }
        .navigationTitle(L10n.gestures)
    }

    private static let longPressMultipliers: [PlaybackSpeed] = [
        .oneQuarter,
        .oneHalf,
        .two,
        .custom(3.0),
        .custom(4.0),
    ]

    private static func normalizedLongPressMultiplier(_ speed: PlaybackSpeed) -> PlaybackSpeed {
        let value = min(max(speed.rawValue, 1.25), 4.0)
        return longPressMultipliers.first(where: { abs($0.rawValue - value) < 0.001 }) ?? .two
    }
}
