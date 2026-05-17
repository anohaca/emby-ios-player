#if os(iOS)
import Combine
import Defaults
import Factory
import Foundation
import SwiftUI
import UIKit

@MainActor
final class LibMPVMediaPlayerProxy: VideoMediaPlayerProxy,
    MediaPlayerOffsetConfigurable,
    MediaPlayerSubtitleConfigurable
{
    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)

    private let controller = MPVPlayerController()
    private weak var playerView: MPVPlayerView?
    private var isAttached = false
    private let shouldForwardLibMPVLogs = {
        let environment = ProcessInfo.processInfo.environment
        return environment["LIBMPVPLAYER_SMOKE_LOG"] != nil ||
            environment["LIBMPVPLAYER_TRACE_LOG"] != nil ||
            environment["LIBMPVPLAYER_DIAGNOSTICS"] != nil
    }()

    weak var manager: MediaPlayerManager? {
        didSet {
            for var observer in observers {
                observer.manager = manager
            }

            guard let manager else { return }
            manager.$playbackItem
                .sink { [weak self] playbackItem in
                    guard let playbackItem else { return }
                    self?.playNew(item: playbackItem)
                }
                .store(in: &cancellables)

            manager.$state
                .sink { [weak self] state in
                    if state == .stopped {
                        self?.playbackStopped()
                    }
                }
                .store(in: &cancellables)
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    private var cancellables: Set<AnyCancellable> = []
    private var currentSubtitleIdentifiers: Set<String> = []
    private var pendingDefaultExternalSubtitleTitle: String?
    private var pendingDefaultExternalSubtitleClearGeneration = 0
    private var convertedEmbeddedSubtitleTitlesByOriginalIndex: [Int: String] = [:]

    init() {
        configureCallbacks()
    }

    deinit {
        controller.shutdown()
    }

    func play() {
        controller.setPaused(false)
    }

    func pause() {
        controller.setPaused(true)
    }

    func stop() {
        controller.stop()
    }

    func jumpForward(_ seconds: Duration) {
        let remaining: Duration
        if let runtime = manager?.item.runtime, let current = manager?.seconds {
            remaining = max(.zero, runtime - current)
        } else {
            remaining = seconds
        }

        let target = min(seconds, remaining)
        guard target > .zero else { return }
        controller.seek(by: target.seconds)
    }

    func jumpBackward(_ seconds: Duration) {
        controller.seek(by: -seconds.seconds)
    }

    func setRate(_ rate: Float) {
        controller.setPlaybackSpeed(Double(rate))
    }

    func setSeconds(_ seconds: Duration) {
        controller.seek(to: seconds.seconds)
    }

    func setAspectFill(_ aspectFill: Bool) {
        playerView?.contentMode = aspectFill ? .scaleAspectFill : .scaleAspectFit
    }

    func setAudioStream(_ stream: MediaStream) {
        guard let trackID = mpvTrackID(for: stream, in: manager?.playbackItem?.audioStreams ?? []) else { return }
        controller.selectAudioTrack(id: trackID)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        guard (stream.index ?? stream.originalIndex ?? -1) >= 0 else {
            controller.disableSubtitle()
            return
        }

        guard let trackID = mpvTrackID(for: stream, in: manager?.playbackItem?.subtitleStreams ?? []) else { return }
        controller.selectSubtitleTrack(id: trackID)
    }

    func setAudioOffset(_ seconds: Duration) {}
    func setSubtitleOffset(_ seconds: Duration) {}
    func setSubtitleColor(_ color: Color) {}
    func setSubtitleFontName(_ fontName: String) {}
    func setSubtitleFontSize(_ fontSize: Int) {}

    var videoPlayerBody: some View {
        LibMPVPlayerRepresentable(proxy: self)
    }

    fileprivate func attach(to view: MPVPlayerView) {
        self.playerView = view

        guard view.window != nil, view.bounds.width > 1, view.bounds.height > 1 else { return }
        guard !isAttached else { return }
        do {
            try controller.attach(to: view)
            isAttached = true
            if let playbackItem = manager?.playbackItem {
                playNew(item: playbackItem)
            }
        } catch {
            manager?.error(ErrorMessage("libmpv failed to initialize: \(error.localizedDescription)"))
        }
    }

    private func configureCallbacks() {
        controller.onTimeChanged = { [weak self] current, _ in
            Task { @MainActor in
                guard let self else { return }
                let seconds = Duration.seconds(current)
                self.manager?.seconds = seconds
                self.manager?.proxy?.isBuffering.value = false
            }
        }

        controller.onPausedChanged = { [weak self] paused in
            Task { @MainActor in
                self?.manager?.setPlaybackRequestStatus(status: paused ? .paused : .playing)
            }
        }

        controller.onVideoRectChanged = { [weak self] rect in
            Task { @MainActor in
                self?.videoSize.value = CGSize(width: rect.width, height: rect.height)
            }
        }

        controller.onSubtitleTracksChanged = { [weak self] tracks, selectedID in
            Task { @MainActor in
                guard let self,
                      let pendingTitle = self.pendingDefaultExternalSubtitleTitle
                else { return }

                if let track = self.pendingDefaultSubtitleTrack(in: tracks, title: pendingTitle) {
                    if selectedID != track.id {
                        self.controller.selectSubtitleTrack(id: track.id)
                    }
                    self.schedulePendingDefaultExternalSubtitleClear(title: pendingTitle)
                } else if selectedID != nil {
                    self.controller.disableSubtitle()
                }
            }
        }

        controller.onFinished = { [weak self] in
            Task { @MainActor in
                guard let self, self.manager?.item.isLiveStream != true else { return }
                self.manager?.ended()
            }
        }

        controller.onError = { [weak self] message in
            Task { @MainActor in
                self?.manager?.error(ErrorMessage("libmpv playback error: \(message)"))
            }
        }

        if shouldForwardLibMPVLogs {
            controller.onLog = { message in
                print("libmpv: \(message)")
            }
        } else {
            controller.onLog = nil
        }
    }

    private func playNew(item: MediaPlayerItem) {
        guard isAttached else { return }

        isBuffering.value = true
        let startSeconds: Duration
        if !item.baseItem.isLiveStream {
            startSeconds = max(.zero, (item.baseItem.startSeconds ?? .zero) - Duration.seconds(Defaults[.VideoPlayer.resumeOffset]))
        } else {
            startSeconds = .zero
        }

        currentSubtitleIdentifiers.removeAll()
        pendingDefaultExternalSubtitleTitle = nil
        pendingDefaultExternalSubtitleClearGeneration += 1
        convertedEmbeddedSubtitleTitlesByOriginalIndex.removeAll()

        applyDefaultTrackLanguageOptions()
        controller.load(url: item.url, headers: item.httpHeaders, startSeconds: startSeconds.seconds)
        controller.setPlaybackSpeed(Double(Defaults[.VideoPlayer.Playback.playbackRate]))
        let addedEmbeddedConvertedSubtitleCount = addEmbeddedConvertedSubtitles(for: item)
        let addedExternalSubtitleURLs = addExternalSubtitles(for: item)
        let addedSubtitleCount = addedEmbeddedConvertedSubtitleCount + addedExternalSubtitleURLs.count + addLocalSubtitles(for: item.url)

        if let audio = defaultAudioStream(for: item) {
            setAudioStream(audio)
        }

        if let subtitle = defaultSubtitleStream(for: item) {
            applyDefaultSubtitleStream(subtitle)
        } else if item.mediaSource.defaultSubtitleStreamIndex == -1 {
            controller.disableSubtitle()
        } else if let defaultSubtitleStreamIndex = item.mediaSource.defaultSubtitleStreamIndex,
                  let subtitle = item.subtitleStreams.first(where: { subtitleStream($0, matchesOriginalOrAdjustedIndex: defaultSubtitleStreamIndex) }) {
            applyDefaultSubtitleStream(subtitle)
        } else if addedSubtitleCount == 0 {
            controller.disableSubtitle()
        }
    }

    private func applyDefaultTrackLanguageOptions() {
        let audio = Defaults[.VideoPlayer.Playback.defaultAudioLanguage]
        let subtitle = Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage]
        controller.setPreferredAudioLanguages(
            audio.mpvLanguageList ??
                (audio == .automatic ? MediaTrackLanguagePreference.automaticAudioMPVLanguageList : nil)
        )
        controller.setPreferredSubtitleLanguages(
            subtitle.mpvLanguageList ??
                (subtitle == .automatic ? MediaTrackLanguagePreference.automaticSubtitleMPVLanguageList : nil)
        )
    }

    private func defaultAudioStream(for item: MediaPlayerItem) -> MediaStream? {
        let preference = Defaults[.VideoPlayer.Playback.defaultAudioLanguage]
        return preference.preferredStream(in: item.audioStreams) ??
            (preference == .automatic ? MediaTrackLanguagePreference.automaticAudioStream(in: item.audioStreams) : nil) ??
            item.audioStreams.first { $0.index == item.mediaSource.defaultAudioStreamIndex }
    }

    private func defaultSubtitleStream(for item: MediaPlayerItem) -> MediaStream? {
        let preference = Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage]
        return preference.preferredStream(in: item.subtitleStreams) ??
            (preference == .automatic ? MediaTrackLanguagePreference.automaticSubtitleStream(in: item.subtitleStreams) : nil)
    }

    private func applyDefaultSubtitleStream(_ subtitle: MediaStream) {
        if isExternalSubtitle(subtitle) {
            if let url = externalSubtitleURL(for: subtitle) {
                controller.disableSubtitle()
                pendingDefaultExternalSubtitleTitle = externalSubtitleTitle(for: subtitle, url: url)
            }
        } else {
            if let originalIndex = subtitleOriginalIndex(subtitle),
               let convertedTitle = convertedEmbeddedSubtitleTitlesByOriginalIndex[originalIndex] {
                controller.disableSubtitle()
                pendingDefaultExternalSubtitleTitle = convertedTitle
                return
            }
            setSubtitleStream(subtitle)
        }
    }

    private func pendingDefaultSubtitleTrack(in tracks: [MPVSubtitleTrack], title: String) -> MPVSubtitleTrack? {
        tracks.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame } ??
            tracks.first {
                $0.title.localizedCaseInsensitiveContains(title) ||
                    title.localizedCaseInsensitiveContains($0.title)
            }
    }

    private func schedulePendingDefaultExternalSubtitleClear(title: String) {
        pendingDefaultExternalSubtitleClearGeneration += 1
        let generation = pendingDefaultExternalSubtitleClearGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self,
                  self.pendingDefaultExternalSubtitleClearGeneration == generation,
                  self.pendingDefaultExternalSubtitleTitle == title
            else { return }

            self.pendingDefaultExternalSubtitleTitle = nil
        }
    }

    private func playbackStopped() {
        controller.stop()
        isBuffering.value = false
    }

    @discardableResult
    private func addEmbeddedConvertedSubtitles(for item: MediaPlayerItem) -> Int {
        let shouldConvert = Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles]
        let client = Container.shared.currentUserSession()?.embyClient
        let itemID = item.baseItem.id
        let mediaSourceID = item.mediaSource.id

        #if DEBUG
        NSLog(
            "EmbyPlayerEmbeddedConvertedSubtitles proxy-enter enabled=%@ item=%@ mediaSource=%@ subtitles=%d",
            shouldConvert.description,
            itemID ?? "<nil>",
            mediaSourceID ?? "<nil>",
            item.subtitleStreams.count
        )
        #endif

        guard shouldConvert,
              let client,
              let itemID,
              let mediaSourceID
        else { return 0 }

        var addedCount = 0
        for stream in item.subtitleStreams where !isExternalSubtitle(stream) {
            guard shouldConvertStreamSubtitle(stream) else { continue }
            guard let originalIndex = subtitleOriginalIndex(stream) else { continue }
            let urls = embeddedSubtitleStreamURLs(itemID: itemID,
                                                  mediaSourceID: mediaSourceID,
                                                  streamIndex: originalIndex,
                                                  stream: stream,
                                                  client: client)
            guard let url = urls.first,
                  MPVSubtitleFileConverter.canConvert(url: url,
                                                      codec: stream.codec,
                                                      isTextSubtitle: stream.isTextSubtitleStream)
            else { continue }

            let title = convertedEmbeddedSubtitleTitle(for: stream, originalIndex: originalIndex)
            let identifier = "emby-embedded-converted://\(itemID)/\(mediaSourceID)/\(originalIndex)"
            if addSubtitleIfNeeded(url: url,
                                   fallbackURLs: Array(urls.dropFirst()),
                                   title: title,
                                   identifier: identifier,
                                   headers: client.playbackHeaders,
                                   stream: stream,
                                   fallbackToOriginal: false) {
                convertedEmbeddedSubtitleTitlesByOriginalIndex[originalIndex] = title
                addedCount += 1
            }
        }

        return addedCount
    }

    @discardableResult
    private func addExternalSubtitles(for item: MediaPlayerItem) -> [(url: URL, title: String)] {
        guard let client = Container.shared.currentUserSession()?.embyClient else { return [] }

        var addedSubtitles: [(url: URL, title: String)] = []
        for stream in item.subtitleStreams where isExternalSubtitle(stream) {
            guard let deliveryURL = stream.deliveryURL,
                  let url = client.absoluteURL(forPathOrURL: deliveryURL)
            else { continue }

            let title = externalSubtitleTitle(for: stream, url: url)
            if addSubtitleIfNeeded(url: url,
                                   title: title,
                                   headers: client.playbackHeaders,
                                   stream: stream) {
                addedSubtitles.append((url, title))
            }
        }

        return addedSubtitles
    }

    @discardableResult
    private func addLocalSubtitles(for mediaURL: URL) -> Int {
        guard mediaURL.isFileURL else { return 0 }
        let urls = (try? MPVSubtitleAutoLoader.matchingSubtitleURLs(for: mediaURL)) ?? []
        return urls.reduce(0) { count, url in
            count + (addSubtitleIfNeeded(url: url, title: nil) ? 1 : 0)
        }
    }

    @discardableResult
    private func addSubtitleIfNeeded(url: URL,
                                     fallbackURLs: [URL] = [],
                                     title: String?,
                                     identifier explicitIdentifier: String? = nil,
                                     headers: [String: String] = [:],
                                     stream: MediaStream? = nil,
                                     fallbackToOriginal: Bool = true) -> Bool {
        let identifier = explicitIdentifier ?? MPVSubtitleAutoLoader.normalizedIdentifier(for: url)
        guard currentSubtitleIdentifiers.insert(identifier).inserted else { return false }
        let shouldConvert = shouldConvertSubtitle(url: url, stream: stream)
        controller.addSubtitle(url: url,
                               fallbackURLs: fallbackURLs,
                               title: title,
                               headers: headers,
                               convertTraditionalChinese: shouldConvert,
                               sourceCodec: stream?.codec,
                               isTextSubtitle: stream?.isTextSubtitleStream,
                               fallbackToOriginal: fallbackToOriginal)
        return true
    }

    private func isExternalSubtitle(_ stream: MediaStream) -> Bool {
        stream.deliveryMethod == .external ||
            stream.isExternal == true ||
            stream.deliveryURL?.isEmpty == false
    }

    private func shouldConvertSubtitle(url: URL, stream: MediaStream?) -> Bool {
        guard Defaults[.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles],
              MPVSubtitleFileConverter.canConvert(url: url,
                                                  codec: stream?.codec,
                                                  isTextSubtitle: stream?.isTextSubtitleStream)
        else {
            return false
        }

        guard let stream else {
            return true
        }

        return shouldConvertStreamSubtitle(stream)
    }

    private func shouldConvertStreamSubtitle(_ stream: MediaStream) -> Bool {
        MediaTrackLanguagePreference.chinese.matches(stream) ||
            MediaTrackLanguagePreference.cantonese.matches(stream)
    }

    private func externalSubtitleURL(for stream: MediaStream) -> URL? {
        guard let client = Container.shared.currentUserSession()?.embyClient else { return nil }
        return externalSubtitleURL(for: stream, client: client)
    }

    private func externalSubtitleURL(for stream: MediaStream, client: EmbyPortSessionClient) -> URL? {
        guard let deliveryURL = stream.deliveryURL, !deliveryURL.isEmpty else { return nil }
        return client.absoluteURL(forPathOrURL: deliveryURL)
    }

    private func embeddedSubtitleStreamURLs(itemID: String,
                                            mediaSourceID: String,
                                            streamIndex: Int,
                                            stream: MediaStream,
                                            client: EmbyPortSessionClient) -> [URL] {
        var seen = Set<String>()
        return embeddedSubtitleExtractionFormats(for: stream).flatMap { format in
            client.subtitleStreamURLs(itemID: itemID,
                                      mediaSourceID: mediaSourceID,
                                      streamIndex: streamIndex,
                                      format: format)
        }.compactMap { url in
            seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    private func embeddedSubtitleExtractionFormats(for stream: MediaStream) -> [String] {
        let codec = normalizedSubtitleCodec(stream.codec)
        switch codec {
        case "ass":
            return ["ass", "srt", "vtt"]
        case "ssa":
            return ["ssa", "srt", "vtt"]
        case "webvtt", "vtt":
            return ["vtt", "srt"]
        default:
            return ["srt", "vtt"]
        }
    }

    private func convertedEmbeddedSubtitleTitle(for stream: MediaStream, originalIndex: Int) -> String {
        let primary = [
            stream.displayTitle,
            stream.title,
        ]
            .compactMap { sanitizedExternalSubtitleTitle($0) }
            .first

        var parts: [String] = [primary ?? "内封字幕 \(originalIndex)"]
        if let language = stream.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(language) }) {
            parts.append(language.uppercased())
        }
        if let codec = stream.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(codec) }) {
            parts.append(codec.uppercased())
        }
        if shouldConvertStreamSubtitle(stream) {
            parts.append("简体")
        }
        return parts.joined(separator: " · ")
    }

    private func normalizedSubtitleCodec(_ codec: String?) -> String {
        codec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased() ?? ""
    }

    private func subtitleOriginalIndex(_ stream: MediaStream) -> Int? {
        stream.originalIndex ?? stream.index
    }

    private func subtitleStream(_ stream: MediaStream, matchesOriginalOrAdjustedIndex index: Int) -> Bool {
        stream.index == index || stream.originalIndex == index
    }

    private func externalSubtitleTitle(for stream: MediaStream, url: URL) -> String {
        let primary = [
            stream.displayTitle,
            stream.title,
        ]
            .compactMap { sanitizedExternalSubtitleTitle($0) }
            .first

        var parts: [String] = []
        if let primary {
            parts.append(primary)
        }

        if let language = stream.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            let uppercased = language.uppercased()
            if !parts.contains(where: { $0.localizedCaseInsensitiveContains(language) }) {
                parts.append(uppercased)
            }
        }

        if let codec = stream.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty {
            let uppercased = codec.uppercased()
            if !parts.contains(where: { $0.localizedCaseInsensitiveContains(codec) }) {
                parts.append(uppercased)
            }
        }

        if stream.isForced == true {
            parts.append("强制")
        }

        if parts.isEmpty {
            let fallback = url.deletingPathExtension().lastPathComponent
            parts.append(fallback.isEmpty || fallback == "Stream" ? "外部字幕" : fallback)
        }

        return parts.joined(separator: " · ")
    }

    private func sanitizedExternalSubtitleTitle(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let stem = (trimmed as NSString).deletingPathExtension
        let genericNames: Set<String> = [
            "stream",
            "subtitle",
            "subtitles",
            "external",
            "external subtitle",
        ]
        if genericNames.contains(trimmed.lowercased()) || genericNames.contains(stem.lowercased()) {
            return nil
        }

        return trimmed
    }

    private func mpvTrackID(for stream: MediaStream, in streams: [MediaStream]) -> String? {
        guard let position = streams.firstIndex(where: { mediaStream($0, matchesOriginalOrAdjustedIndexesOf: stream) }) else {
            return nil
        }

        return String(position + 1)
    }

    private func mediaStream(_ candidate: MediaStream, matchesOriginalOrAdjustedIndexesOf stream: MediaStream) -> Bool {
        let indexes = [stream.index, stream.originalIndex].compactMap(\.self)
        return indexes.contains { candidate.index == $0 || candidate.originalIndex == $0 }
    }
}

private struct LibMPVPlayerRepresentable: UIViewRepresentable {
    let proxy: LibMPVMediaPlayerProxy

    func makeUIView(context: Context) -> MPVPlayerView {
        let view = MPVPlayerView()
        view.onReadyForRendering = { view in
            proxy.attach(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: MPVPlayerView, context: Context) {
        proxy.attach(to: uiView)
    }
}
#endif
