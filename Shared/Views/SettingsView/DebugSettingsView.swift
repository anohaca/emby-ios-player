//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// NOTE: All settings *MUST* be surrounded by DEBUG compiler conditional as usage site

// swiftlint:disable hard_coded_display_string

#if DEBUG
struct DebugSettingsView: View {

    private static let softwareVideoDecoderCodecs = MPVClientBridge.softwareVideoDecoderCodecs()
    private static let softwareVideoRangeCapabilities =
        MPVClientBridge.softwareVideoRangeProcessingCapabilities()

    @Default(.sendProgressReports)
    private var sendProgressReports

    var body: some View {
        Form(systemImage: "ladybug") {

            Section(L10n.settings) {
                Toggle(L10n.sendProgressReports, isOn: $sendProgressReports)
            }

            Section("Device Details") {
                LabeledContent(
                    "SoC & GPU",
                    value: PlaybackCapabilities.gpuName
                )

                LabeledContent(
                    "Device Reports HDR Capabilities",
                    value: PlaybackCapabilities.isDeviceHDRCapable ? L10n.yes : L10n.no
                )
            }

            Section("Hardware Video Decode Support") {
                LabeledContent(
                    VideoCodec.h264.displayTitle,
                    value: PlaybackCapabilities.supportsH264 ? L10n.yes : L10n.no
                )

                LabeledContent(
                    VideoCodec.av1.displayTitle,
                    value: PlaybackCapabilities.supportsAV1 ? L10n.yes : L10n.no
                )

                LabeledContent(
                    VideoCodec.hevc.displayTitle,
                    value: PlaybackCapabilities.supportsHEVC ? L10n.yes : L10n.no
                )

                LabeledContent(
                    VideoCodec.vp9.displayTitle,
                    value: PlaybackCapabilities.supportsVP9 ? L10n.yes : L10n.no
                )
            }

            Section("Software Video Decode Support") {
                softwareDecoderRow(VideoCodec.h264, aliases: ["h264"])
                softwareDecoderRow(VideoCodec.hevc, aliases: ["hevc", "h265"])
                softwareDecoderRow(VideoCodec.av1, aliases: ["av1"])
                softwareDecoderRow(VideoCodec.vp9, aliases: ["vp9"])
            }

            Section("Hardware Video Range Support") {
                LabeledContent(
                    VideoRangeType.hdr10.displayTitle,
                    value: PlaybackCapabilities.supportsHDR10 ? L10n.yes : L10n.no
                )

                LabeledContent(
                    VideoRangeType.hlg.displayTitle,
                    value: PlaybackCapabilities.supportsHLG ? L10n.yes : L10n.no
                )

                LabeledContent(
                    VideoRangeType.dovi.displayTitle,
                    value: PlaybackCapabilities.supportsDolbyVision ? L10n.yes : L10n.no
                )
            }

            Section("Software Video Range Processing") {
                softwareVideoRangeRow(VideoRangeType.hdr10, capability: "hdr10")
                softwareVideoRangeRow(VideoRangeType.hdr10Plus, capability: "hdr10plus")
                softwareVideoRangeRow(VideoRangeType.hlg, capability: "hlg")
                softwareVideoRangeRow(VideoRangeType.dovi, capability: "dovi")
            }
        }
        .labeledContentStyle(.focusable)
        .navigationTitle("Debug")
    }

    private func softwareDecoderRow(_ codec: VideoCodec, aliases: Set<String>) -> some View {
        LabeledContent(
            codec.displayTitle,
            value: !Self.softwareVideoDecoderCodecs.isDisjoint(with: aliases) ? L10n.yes : L10n.no
        )
    }

    private func softwareVideoRangeRow(_ range: VideoRangeType, capability: String) -> some View {
        LabeledContent(
            range.displayTitle,
            value: Self.softwareVideoRangeCapabilities.contains(capability) ? L10n.yes : L10n.no
        )
    }
}
#endif
