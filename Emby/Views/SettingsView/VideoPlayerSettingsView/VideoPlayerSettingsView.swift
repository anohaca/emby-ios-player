//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct VideoPlayerSettingsView: View {

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardLength
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardLength
    @Default(.VideoPlayer.resumeOffset)
    private var resumeOffset
    @Default(.VideoPlayer.Playback.playbackRate)
    private var playbackRate
    @Default(.VideoPlayer.Playback.defaultAudioLanguage)
    private var defaultAudioLanguage
    @Default(.VideoPlayer.Subtitle.defaultSubtitleLanguage)
    private var defaultSubtitleLanguage
    @Default(.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles)
    private var convertTraditionalChineseSubtitles

    @Router
    private var router

    var body: some View {
        Form {

            Section(L10n.playbackSpeed) {
                Picker(L10n.playbackSpeed, selection: $playbackRate) {
                    ForEach(Self.playbackRates, id: \.self) { rate in
                        Text(rate, format: .playbackRate(precision: 2))
                            .tag(rate)
                    }
                }
            }

            Section {
                Picker("默认音轨语言", selection: $defaultAudioLanguage) {
                    ForEach(MediaTrackLanguagePreference.allCases, id: \.self) { language in
                        Text(language.displayTitle)
                            .tag(language)
                    }
                }

                Picker("默认字幕语言", selection: $defaultSubtitleLanguage) {
                    ForEach(MediaTrackLanguagePreference.allCases, id: \.self) { language in
                        Text(language.displayTitle)
                            .tag(language)
                    }
                }
            } header: {
                Text("默认轨道")
            } footer: {
                Text("选择“自动”时会优先日语音轨和中文字幕，找不到再使用服务器或文件默认轨道。")
            }

            Section(L10n.jump) {
                JumpIntervalPicker(L10n.jumpBackwardLength, selection: $jumpBackwardLength)
                JumpIntervalPicker(L10n.jumpForwardLength, selection: $jumpForwardLength)
            }

            Section {
                Stepper(value: $resumeOffset, in: 0 ... 30, step: 1) {
                    LabeledContent(L10n.resumeOffset) {
                        Text(resumeOffset, format: SecondFormatter())
                    }
                }
            } footer: {
                Text(L10n.resumeOffsetDescription)
            }

            Section {
                ChevronButton(L10n.gestures) {
                    router.route(to: .gestureSettings)
                }
            }

            Section {
                Toggle("繁体字幕转简体", isOn: $convertTraditionalChineseSubtitles)
            } header: {
                Text("字幕兼容")
            } footer: {
                Text("仅文本字幕会转换，PGS/VobSub 等图片字幕保持原样。")
            }

            ButtonSection()
                .disabled(true)
                .foregroundStyle(.secondary)

            SupplementSection()
                .disabled(true)
                .foregroundStyle(.secondary)

            SliderSection()
                .disabled(true)
                .foregroundStyle(.secondary)

            SubtitleSection()
                .disabled(true)
                .foregroundStyle(.secondary)

            TimestampSection()
                .disabled(true)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            playbackRate = Self.normalizedPlaybackRate(playbackRate)
        }
        .navigationTitle(L10n.videoPlayer.localizedCapitalized)
    }

    private static let playbackRates: [Float] = [
        0.5,
        0.75,
        1.0,
        1.25,
        1.5,
        2.0,
        3.0,
        4.0,
    ]

    private static func normalizedPlaybackRate(_ rate: Float) -> Float {
        guard playbackRates.contains(where: { abs($0 - rate) < 0.001 }) else {
            return 1.0
        }

        return min(max(rate, playbackRates[0]), playbackRates[playbackRates.count - 1])
    }
}
