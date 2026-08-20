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
    @Default(.VideoPlayer.showSkipIntroButton)
    private var showSkipIntroButton

    @Default(.VideoPlayer.skipIntroSeconds)
    private var skipIntroSeconds
    @Default(.VideoPlayer.showEndNextEpisodeButton)
    private var showEndNextEpisodeButton
    @Default(.VideoPlayer.endNextEpisodeCountdownSeconds)
    private var endNextEpisodeCountdownSeconds
    @Default(.VideoPlayer.resumeOffset)
    private var resumeOffset
    @Default(.VideoPlayer.Playback.playbackRate)
    private var playbackRate
    @Default(.VideoPlayer.Playback.defaultAudioLanguage)
    private var defaultAudioLanguage
    @Default(.VideoPlayer.Playback.mpvCacheEnabled)
    private var mpvCacheEnabled
    @Default(.VideoPlayer.Playback.mpvDemuxerMaxBytesMiB)
    private var mpvDemuxerMaxBytesMiB
    @Default(.VideoPlayer.Playback.mpvDemuxerMaxBackBytesMiB)
    private var mpvDemuxerMaxBackBytesMiB
    @Default(.VideoPlayer.Playback.mpvDemuxerReadaheadSeconds)
    private var mpvDemuxerReadaheadSeconds
    @Default(.VideoPlayer.Playback.mpvCachePauseEnabled)
    private var mpvCachePauseEnabled
    @Default(.VideoPlayer.Transition.continuePlayingInBackground)
    private var continuePlayingInBackground

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
                Toggle("进入后台继续播放", isOn: $continuePlayingInBackground)
            } footer: {
                Text("关闭时，视频进入后台会暂停，并在返回播放器后继续。开启时，进入后台仍会播放音频。")
            }

            Section {
                Picker("默认音轨语言", selection: $defaultAudioLanguage) {
                    ForEach(MediaTrackLanguagePreference.allCases, id: \.self) { language in
                        Text(language.displayTitle)
                            .tag(language)
                    }
                }

            } header: {
                Text("默认音轨")
            } footer: {
                Text("选择“自动”时会优先日语音轨，找不到再使用服务器或文件默认音轨。")
            }

            Section {
                Toggle("启用缓存", isOn: $mpvCacheEnabled)

                Stepper(value: $mpvDemuxerMaxBytesMiB, in: 0 ... 2048, step: 16) {
                    LabeledContent("前向缓存") {
                        Text("\(mpvDemuxerMaxBytesMiB) MiB")
                    }
                }
                .disabled(!mpvCacheEnabled)

                Stepper(value: $mpvDemuxerMaxBackBytesMiB, in: 0 ... 1024, step: 16) {
                    LabeledContent("回退缓存") {
                        Text("\(mpvDemuxerMaxBackBytesMiB) MiB")
                    }
                }
                .disabled(!mpvCacheEnabled)

                Stepper(value: $mpvDemuxerReadaheadSeconds, in: 0 ... 300, step: 5) {
                    LabeledContent("预读时间") {
                        Text("\(mpvDemuxerReadaheadSeconds) 秒")
                    }
                }
                .disabled(!mpvCacheEnabled)

                Toggle("缓存不足时暂停", isOn: $mpvCachePauseEnabled)
                    .disabled(!mpvCacheEnabled)

            } header: {
                Text("mpv 缓存")
            } footer: {
                Text("这些选项会在每次打开视频前写入 mpv。增大缓存可改善网络抖动，但会占用更多内存。")
            }

            Section(L10n.jump) {
                JumpIntervalPicker(L10n.jumpBackwardLength, selection: $jumpBackwardLength)
                JumpIntervalPicker(L10n.jumpForwardLength, selection: $jumpForwardLength)
                Toggle("显示跳过片头按钮", isOn: $showSkipIntroButton)
                Stepper(value: $skipIntroSeconds, in: 5 ... 300, step: 5) {
                    LabeledContent("跳过片头默认时长") {
                        HStack(spacing: 4) {
                            ClearSettingsIntegerField(value: $skipIntroSeconds)
                            Text("秒")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!showSkipIntroButton)
                Toggle("显示片尾下一集按钮", isOn: $showEndNextEpisodeButton)
                Stepper(value: $endNextEpisodeCountdownSeconds, in: 10 ... 600, step: 10) {
                    LabeledContent("下一集按钮出现时间") {
                        HStack(spacing: 4) {
                            Text("倒数")
                                .foregroundStyle(.secondary)
                            ClearSettingsIntegerField(value: $endNextEpisodeCountdownSeconds)
                            Text("秒")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!showEndNextEpisodeButton)
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
