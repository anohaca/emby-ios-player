//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: adjust button sizes/padding on compact/regular?
// TODO: jump rotation symbol effects

extension VideoPlayer.PlaybackControls {

    struct PlaybackButtons: View {

        @Default(.VideoPlayer.jumpBackwardInterval)
        private var jumpBackwardInterval
        @Default(.VideoPlayer.jumpForwardInterval)
        private var jumpForwardInterval

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        private func onPressed(isPressed: Bool) {
            if isPressed {
                containerState.timer.stop()
            } else {
                containerState.timer.poke()
            }
        }

        private var shouldShowJumpButtons: Bool {
            !manager.item.isLiveStream
        }

        @ViewBuilder
        private var playButton: some View {
            Button {
                switch manager.playbackRequestStatus {
                case .playing:
                    manager.setPlaybackRequestStatus(status: .paused)
                case .paused:
                    manager.setPlaybackRequestStatus(status: .playing)
                }
            } label: {
                Group {
                    switch manager.playbackRequestStatus {
                    case .playing:
                        Label(L10n.pause, systemImage: "pause.fill")
                    case .paused:
                        Label(L10n.play, systemImage: "play.fill")
                    }
                }
                .transition(.opacity.combined(with: .scale).animation(.bouncy(duration: 0.7, extraBounce: 0.2)))
                .font(.system(size: 36, weight: .bold, design: .default))
                .contentShape(Rectangle())
                .labelStyle(.iconOnly)
                .padding(20)
            }
        }

        @ViewBuilder
        private var jumpForwardButton: some View {
            Button {
                manager.proxy?.jumpForward(jumpForwardInterval.rawValue)
            } label: {
                JumpIntervalIcon(interval: jumpForwardInterval, direction: .forward)
                    .padding(10)
            }
            .accessibilityLabel(Text("前进 \(jumpForwardInterval.rawValue, format: Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .narrow))"))
            .foregroundStyle(.primary)
        }

        @ViewBuilder
        private var jumpBackwardButton: some View {
            Button {
                manager.proxy?.jumpBackward(jumpBackwardInterval.rawValue)
            } label: {
                JumpIntervalIcon(interval: jumpBackwardInterval, direction: .backward)
                    .padding(10)
            }
            .accessibilityLabel(Text("后退 \(jumpBackwardInterval.rawValue, format: Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .narrow))"))
            .foregroundStyle(.primary)
        }

        var body: some View {
            HStack(spacing: 0) {
                if shouldShowJumpButtons {
                    jumpBackwardButton
                }

                playButton
                    .frame(minWidth: 50, maxWidth: 150)

                if shouldShowJumpButtons {
                    jumpForwardButton
                }
            }
            .buttonStyle(OverlayButtonStyle(onPressed: onPressed))
            .padding(.horizontal, 50)
        }
    }

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

    private struct JumpIntervalIcon: View {

        let interval: MediaJumpInterval
        let direction: JumpDirection

        var body: some View {
            Group {
                if interval.usesNativeNumberedSystemImage || interval.iconText == nil {
                    Image(systemName: direction.systemImage(for: interval))
                        .font(.system(size: 32, weight: .regular, design: .default))
                } else {
                    ZStack {
                        Image(systemName: direction.baseSystemImage)
                            .font(.system(size: 32, weight: .regular, design: .default))

                        if let iconText = interval.iconText {
                            Text(iconText)
                                .font(.system(size: iconText.count == 1 ? 11 : 9, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .offset(y: 0.4)
                        }
                    }
                }
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)
        }
    }
}
