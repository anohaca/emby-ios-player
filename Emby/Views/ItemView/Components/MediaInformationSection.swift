//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct MediaInformationSection: View {

        let sources: [MediaSourceInfo]
        let selectedSubtitleStreamIndex: Int?
        let selectedSubtitleRequiredFonts: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("媒体信息")
                    .font(.title2.bold())
                    .edgePadding(.horizontal)

                ForEach(sources.indices, id: \.self) { index in
                    let source = sources[index]
                    VStack(alignment: .leading, spacing: 12) {
                        if sources.count > 1 {
                            Text(source.name ?? "版本 \(index + 1)")
                                .font(.headline)
                                .edgePadding(.horizontal)
                        }

                        StreamCardsRow(
                            streams: sortedStreams(source.mediaStreams ?? []),
                            identity: source.id ?? "source-\(index)",
                            selectedSubtitleStreamIndex: selectedSubtitleStreamIndex,
                            selectedSubtitleRequiredFonts: selectedSubtitleRequiredFonts,
                            allMediaStreams: source.mediaStreams ?? []
                        )

                        SourceCard(source: source)
                            .edgePadding(.horizontal)
                    }
                }
            }
        }

        private func sortedStreams(_ streams: [MediaStream]) -> [MediaStream] {
            streams.enumerated().sorted { lhs, rhs in
                let lhsPriority = priority(of: lhs.element)
                let rhsPriority = priority(of: rhs.element)
                return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
            }.map(\.element)
        }

        private func priority(of stream: MediaStream) -> Int {
            switch stream.type {
            case .subtitle where stream.index == selectedSubtitleStreamIndex: 0
            case .video: 1
            case .audio: 2
            case .embeddedImage: 3
            case .subtitle: 4
            default: 5
            }
        }

    }
}

private extension ItemView.MediaInformationSection {

    struct StreamCardsRow: View {

        let streams: [MediaStream]
        let identity: String
        let selectedSubtitleStreamIndex: Int?
        let selectedSubtitleRequiredFonts: [String]
        let allMediaStreams: [MediaStream]

        @State
        private var maximumCardHeight: CGFloat = 0

        var body: some View {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(streams.indices, id: \.self) { index in
                        StreamCard(
                            stream: streams[index],
                            height: maximumCardHeight > 0 ? maximumCardHeight : nil,
                            requiredFonts: streams[index].type == .subtitle &&
                                streams[index].index == selectedSubtitleStreamIndex ? selectedSubtitleRequiredFonts : [],
                            allMediaStreams: allMediaStreams
                        )
                    }
                }
                .edgePadding(.horizontal)
                .onPreferenceChange(StreamCardHeightPreferenceKey.self) { height in
                    if height > maximumCardHeight {
                        maximumCardHeight = height
                    }
                }
            }
            .scrollIndicators(.hidden)
            .id(identity)
        }
    }

    struct StreamCard: View {

        let stream: MediaStream
        let height: CGFloat?
        let requiredFonts: [String]
        let allMediaStreams: [MediaStream]

        @State
        private var isMatchingFonts = false
        @State
        private var fontStatusRevision = 0

        private var title: String {
            switch stream.type {
            case .video: "视频"
            case .audio: "音频"
            case .subtitle: "字幕"
            case .embeddedImage: "图片"
            case .attachment: "附件"
            case .lyric: "歌词"
            case .data: "数据"
            default: "媒体"
            }
        }

        private var systemImage: String {
            switch stream.type {
            case .video: "video"
            case .audio: "speaker.wave.2"
            case .subtitle: "captions.bubble"
            case .embeddedImage: "photo"
            case .attachment: "paperclip"
            default: "waveform"
            }
        }

        private var properties: [(String, String)] {
            stream.mediaInformationProperties
        }

        private var fontStatuses: [(name: String, status: String)] {
            _ = fontStatusRevision
            return requiredFonts.map {
                ($0, SubtitleFontManager.loadStatus(for: $0, mediaStreams: allMediaStreams))
            }
        }

        private var missingFonts: [String] {
            fontStatuses.filter { $0.status == "缺失" }.map(\.name)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                ForEach(properties.indices, id: \.self) { index in
                    let property = properties[index]
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(property.0)
                            .foregroundStyle(.primary)
                        Text(property.1)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                }

                if requiredFonts.isNotEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("所需字体")
                        Text(fontStatuses.map { "\($0.name)：\($0.status)" }.joined(separator: "\n"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)

                    if missingFonts.isNotEmpty || isMatchingFonts {
                        Button {
                            matchMissingFonts()
                        } label: {
                            if isMatchingFonts {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("匹配缺失字体", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isMatchingFonts)
                    }
                }
            }
            .frame(width: 280, alignment: .topLeading)
            .padding(16)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: StreamCardHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .frame(height: height, alignment: .topLeading)
            .background(Color.secondarySystemFill, in: RoundedRectangle(cornerRadius: 8))
        }

        private func matchMissingFonts() {
            let fonts = missingFonts
            guard fonts.isNotEmpty else { return }
            isMatchingFonts = true
            Task {
                await SubtitleFontManager.ensureFonts(fonts, ignoringAutomaticDownloadSetting: true)
                await MainActor.run {
                    fontStatusRevision += 1
                    isMatchingFonts = false
                }
            }
        }
    }

    struct SourceCard: View {

        let source: MediaSourceInfo

        private var sizeLabel: String? {
            source.size.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            }
        }

        private var details: String {
            [source.name, source.container?.uppercased(), sizeLabel]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  ")
        }

        var body: some View {
            VStack(spacing: 6) {
                if !details.isEmpty {
                    Text(details)
                }
                if let path = source.path, !path.isEmpty {
                    Text(path)
                        .textSelection(.enabled)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color.secondarySystemFill, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    struct StreamCardHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

private extension MediaStream {

    var mediaInformationProperties: [(String, String)] {
        var result: [(String, String)] = []
        appendMediaProperty("标题", displayTitle ?? title, to: &result)
        appendMediaProperty("内嵌标题", title, to: &result, unlessEqualTo: displayTitle)
        appendMediaProperty("编码", codec, to: &result)

        if let width, let height {
            result.append(("分辨率", "\(width)x\(height)"))
        }
        if let frameRate = realFrameRate ?? averageFrameRate {
            result.append(("帧率", String(format: "%.3f", frameRate)))
        }

        appendMediaProperty("语言", language, to: &result)
        appendMediaProperty("布局", channelLayout, to: &result)
        appendMediaProperty("声道", channels.map(String.init), to: &result)
        appendMediaProperty("比特率", bitRate.map { $0.formatted(.bitRate) }, to: &result)
        appendMediaProperty("采样率", sampleRate.map { "\($0) Hz" }, to: &result)
        appendMediaProperty("动态范围", videoRange?.rawValue, to: &result)
        appendMediaProperty("配置", profile, to: &result)
        appendMediaProperty("等级", level.map { String($0) }, to: &result)
        appendMediaProperty("长宽比", aspectRatio, to: &result)
        appendMediaProperty("交错", isInterlaced.map(yesNo), to: &result)
        appendMediaProperty("基色", colorPrimaries, to: &result)
        appendMediaProperty("色域", colorSpace, to: &result)
        appendMediaProperty("色偏", colorTransfer, to: &result)
        appendMediaProperty("位深", bitDepth.map(String.init), to: &result)
        appendMediaProperty("像素格式", pixelFormat, to: &result)
        appendMediaProperty("外部", isExternal.map(yesNo), to: &result)
        appendMediaProperty("默认", isDefault.map(yesNo), to: &result)
        appendMediaProperty("强制", isForced.map(yesNo), to: &result)
        return result
    }

    func appendMediaProperty(
        _ label: String,
        _ value: String?,
        to result: inout [(String, String)],
        unlessEqualTo otherValue: String? = nil
    ) {
        guard let value, !value.isEmpty, value != otherValue else { return }
        result.append((label, value))
    }

    func yesNo(_ value: Bool) -> String {
        value ? "是" : "否"
    }
}
