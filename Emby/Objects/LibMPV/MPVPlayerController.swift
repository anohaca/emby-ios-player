import AVFoundation
import Foundation
import QuartzCore

struct MPVVideoRect {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let osdWidth: Double
    let osdHeight: Double
    let marginLeft: Double
    let marginRight: Double
    let marginTop: Double
    let marginBottom: Double
}

struct MPVSubtitleTrack {
    let id: String
    let title: String
    let isSelected: Bool
    let language: String?
    let codec: String?
    let isExternal: Bool

    init(id: String,
         title: String,
         isSelected: Bool,
         language: String? = nil,
         codec: String? = nil,
         isExternal: Bool = false) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
        self.language = language
        self.codec = codec
        self.isExternal = isExternal
    }

    var supportsTraditionalToSimplifiedConversion: Bool {
        guard let codec = codec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !codec.isEmpty
        else {
            return !titleMatchesImageSubtitle
        }

        let normalized = codec
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        if Self.imageSubtitleCodecs.contains(normalized) {
            return false
        }
        if Self.textSubtitleCodecs.contains(normalized) {
            return true
        }

        return !titleMatchesImageSubtitle
    }

    private var titleMatchesImageSubtitle: Bool {
        let normalizedTitle = title
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return Self.imageSubtitleTitleMarkers.contains { normalizedTitle.contains($0) }
    }

    private static let textSubtitleCodecs: Set<String> = [
        "ass",
        "eia_608",
        "eia_708",
        "hdmv_text_subtitle",
        "jacosub",
        "microdvd",
        "mov_text",
        "mpl2",
        "pjs",
        "realtext",
        "sami",
        "ssa",
        "srt",
        "stl",
        "subrip",
        "subviewer",
        "subviewer1",
        "text",
        "vplayer",
        "webvtt",
    ]

    private static let imageSubtitleCodecs: Set<String> = [
        "dvd_subtitle",
        "dvdsub",
        "dvb_subtitle",
        "dvbsub",
        "hdmv_pgs_subtitle",
        "pgs",
        "sup",
        "vobsub",
        "xsub",
    ]

    private static let imageSubtitleTitleMarkers = [
        "pgs",
        "sup",
        "vobsub",
        "dvd subtitle",
        "dvd_subtitle",
        "hdmv_pgs",
    ]
}

enum ChineseSubtitleConverter {
    static func traditionalToSimplified(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        let didTransform = CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return didTransform ? mutable as String : text
    }
}

enum MPVSubtitleFileConverter {
    private static let textSubtitleExtensions: Set<String> = [
        "ass",
        "sami",
        "smi",
        "srt",
        "ssa",
        "vtt",
        "webvtt",
    ]

    private static let imageSubtitleExtensions: Set<String> = [
        "idx",
        "sup",
    ]

    private static let textSubtitleCodecs: Set<String> = [
        "ass",
        "eia_608",
        "eia_708",
        "hdmv_text_subtitle",
        "jacosub",
        "microdvd",
        "mov_text",
        "mpl2",
        "pjs",
        "realtext",
        "sami",
        "ssa",
        "srt",
        "stl",
        "subrip",
        "subviewer",
        "subviewer1",
        "text",
        "vplayer",
        "webvtt",
    ]

    private static let imageSubtitleCodecs: Set<String> = [
        "dvd_subtitle",
        "dvdsub",
        "dvb_subtitle",
        "dvbsub",
        "hdmv_pgs_subtitle",
        "pgs",
        "sup",
        "vobsub",
        "xsub",
    ]

    static func canConvert(url: URL, codec: String?, isTextSubtitle: Bool?) -> Bool {
        if isTextSubtitle == true {
            return true
        }
        if isTextSubtitle == false {
            guard let codec, normalizedCodec(codec).isEmpty == false else {
                return false
            }
            return textSubtitleCodecs.contains(normalizedCodec(codec))
        }

        if let codec, normalizedCodec(codec).isEmpty == false {
            let normalized = normalizedCodec(codec)
            if imageSubtitleCodecs.contains(normalized) {
                return false
            }
            if textSubtitleCodecs.contains(normalized) {
                return true
            }
        }

        let fileExtension = url.pathExtension.lowercased()
        if imageSubtitleExtensions.contains(fileExtension) {
            return false
        }
        return textSubtitleExtensions.contains(fileExtension)
    }

    static func convertedSubtitleURL(for url: URL,
                                     headers: [String: String],
                                     codec: String?,
                                     isTextSubtitle: Bool?) -> URL? {
        guard canConvert(url: url, codec: codec, isTextSubtitle: isTextSubtitle) else {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert result=skip path=%@ codec=%@ text=%@",
                  safeLogPath(for: url),
                  codec ?? "<nil>",
                  isTextSubtitle.map(\.description) ?? "<nil>")
            #endif
            return nil
        }

        guard let data = loadData(from: url, headers: headers) else {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert result=load-failed path=%@", safeLogPath(for: url))
            #endif
            return nil
        }

        guard let text = decodeSubtitle(data) else {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert result=decode-failed path=%@ bytes=%d",
                  safeLogPath(for: url),
                  data.count)
            #endif
            return nil
        }

        let convertedText = ChineseSubtitleConverter.traditionalToSimplified(text)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbyConvertedSubtitles", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDirectory,
                                                    withIntermediateDirectories: true)
            let outputURL = outputDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(outputExtension(for: url, codec: codec))
            try convertedText.data(using: .utf8)?.write(to: outputURL, options: .atomic)
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert result=success path=%@ output=%@ bytes=%d",
                  safeLogPath(for: url),
                  outputURL.lastPathComponent,
                  data.count)
            #endif
            return outputURL
        } catch {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert result=write-failed path=%@ error=%@",
                  safeLogPath(for: url),
                  error.localizedDescription)
            #endif
            return nil
        }
    }

    static func convertedSubtitleURL(for urls: [URL],
                                     headers: [String: String],
                                     codec: String?,
                                     isTextSubtitle: Bool?) -> URL? {
        for (index, url) in urls.enumerated() {
            #if DEBUG
            NSLog("EmbyPlayerSubtitleConvert candidate=%d path=%@", index, safeLogPath(for: url))
            #endif
            if let convertedURL = convertedSubtitleURL(for: url,
                                                       headers: headers,
                                                       codec: codec,
                                                       isTextSubtitle: isTextSubtitle) {
                return convertedURL
            }
        }
        return nil
    }

    private static func safeLogPath(for url: URL) -> String {
        url.isFileURL ? url.path : url.path
    }

    private static func loadData(from url: URL, headers: [String: String]) -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        headers.forEach { name, value in
            request.setValue(value, forHTTPHeaderField: name)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                semaphore.signal()
                return
            }
            result = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }

    private static func decodeSubtitle(_ data: Data) -> String? {
        for encoding in candidateEncodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return String(data: data, encoding: .utf8)
    }

    private static var candidateEncodings: [String.Encoding] {
        [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            stringEncoding(for: .GB_18030_2000),
            stringEncoding(for: .big5),
        ]
    }

    private static func stringEncoding(for encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    private static func outputExtension(for url: URL, codec: String?) -> String {
        let fileExtension = url.pathExtension.lowercased()
        if textSubtitleExtensions.contains(fileExtension) {
            return fileExtension == "webvtt" ? "vtt" : fileExtension
        }

        switch normalizedCodec(codec ?? "") {
        case "ass":
            return "ass"
        case "ssa":
            return "ssa"
        case "sami":
            return "smi"
        case "webvtt":
            return "vtt"
        default:
            return "srt"
        }
    }

    private static func normalizedCodec(_ codec: String) -> String {
        codec
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }
}

enum MPVSubtitleAutoLoader {
    static let subtitleExtensions: Set<String> = [
        "ass",
        "idx",
        "smi",
        "srt",
        "ssa",
        "sub",
        "sup",
        "vtt"
    ]

    static func normalizedIdentifier(for url: URL) -> String {
        if url.isFileURL {
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        }

        return url.absoluteString
    }

    static func matchingSubtitleURLs(for mediaURL: URL) throws -> [URL] {
        guard mediaURL.isFileURL else { return [] }

        let directoryURL = mediaURL.deletingLastPathComponent()
        let mediaStem = mediaURL.deletingPathExtension().lastPathComponent
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var candidates = fileURLs.filter { url in
            guard url.isFileURL else { return false }
            guard subtitleExtensions.contains(url.pathExtension.lowercased()) else { return false }
            return subtitleNameMatchesMedia(
                url.deletingPathExtension().lastPathComponent,
                mediaStem: mediaStem
            )
        }

        let idxStems = Set(candidates
            .filter { $0.pathExtension.lowercased() == "idx" }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        if !idxStems.isEmpty {
            candidates.removeAll { url in
                url.pathExtension.lowercased() == "sub" &&
                    idxStems.contains(url.deletingPathExtension().lastPathComponent.lowercased())
            }
        }

        return candidates.sorted { lhs, rhs in
            let lhsStem = lhs.deletingPathExtension().lastPathComponent
            let rhsStem = rhs.deletingPathExtension().lastPathComponent
            let lhsExact = lhsStem.localizedCaseInsensitiveCompare(mediaStem) == .orderedSame
            let rhsExact = rhsStem.localizedCaseInsensitiveCompare(mediaStem) == .orderedSame
            if lhsExact != rhsExact {
                return lhsExact
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    static func subtitleNameMatchesMedia(_ subtitleStem: String, mediaStem: String) -> Bool {
        if subtitleStem.localizedCaseInsensitiveCompare(mediaStem) == .orderedSame {
            return true
        }

        let subtitle = subtitleStem.lowercased()
        let media = mediaStem.lowercased()
        return subtitle.hasPrefix(media + ".") ||
            subtitle.hasPrefix(media + "-") ||
            subtitle.hasPrefix(media + "_")
    }
}

final class MPVPlayerController: NSObject {
    var onTimeChanged: ((Double, Double) -> Void)?
    var onPausedChanged: ((Bool) -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onVideoRectChanged: ((MPVVideoRect) -> Void)?
    var onFirstFrameRendered: (() -> Void)?
    var onFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onSubtitleTracksChanged: (([MPVSubtitleTrack], String?) -> Void)?
    var onSubtitleTextChanged: ((String?) -> Void)?

    private var bridge: MPVClientBridge?
    private var scopedURL: URL?
    private var scopedAccess = false
    private var scopedSubtitleURLs: [URL] = []
    private var convertedSubtitleURLs: [URL] = []
    private var subtitleLoadGeneration = 0

    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused: Bool = true
    private(set) var isBuffering: Bool = false
    private(set) var playbackSpeed: Double = 1.0

    func attach(to playerView: MPVPlayerView) throws {
        if bridge != nil {
            return
        }

        try configureAudioSession()

        let bridge = MPVClientBridge(layer: playerView.metalLayer)
        bridge.delegate = self

        try bridge.initializePlayer()
        bridge.setPlaybackSpeed(playbackSpeed)

        self.bridge = bridge
    }

    func load(url: URL, headers: [String: String] = [:], startSeconds: Double = 0) {
        releaseScopedURL()
        releaseScopedSubtitleURLs()
        releaseConvertedSubtitleURLs()
        subtitleLoadGeneration += 1
        if url.isFileURL {
            scopedAccess = url.startAccessingSecurityScopedResource()
            scopedURL = url
        }

        bridge?.load(url, headers: headers, startSeconds: startSeconds)
        setPaused(false)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        bridge?.setPaused(paused)
        onPausedChanged?(paused)
    }

    func setMuted(_ muted: Bool) {
        bridge?.setMuted(muted)
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = min(max(speed, 0.25), 4.0)
        bridge?.setPlaybackSpeed(playbackSpeed)
    }

    func setPreferredAudioLanguages(_ languages: String?) {
        bridge?.setPreferredAudioLanguages(languages)
    }

    func setPreferredSubtitleLanguages(_ languages: String?) {
        bridge?.setPreferredSubtitleLanguages(languages)
    }

    func setSubtitlePosition(_ position: Double) {
        bridge?.setSubtitlePosition(min(max(position, 0), 100))
    }

    func setSubtitleScale(_ scale: Double) {
        bridge?.setSubtitleScale(min(max(scale, 0.5), 2.5))
    }

    func setSubtitleBorderSize(_ borderSize: Double) {
        bridge?.setSubtitleBorderSize(min(max(borderSize, 0), 8))
    }

    func seek(to seconds: Double) {
        let target: Double
        if duration > 0 {
            target = min(max(0, seconds), duration)
        } else {
            target = max(0, seconds)
        }
        bridge?.seek(toSeconds: target)
    }

    func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func refreshVideoRect() {
        bridge?.refreshVideoRect()
    }

    func stop() {
        isPaused = true
        subtitleLoadGeneration += 1
        releaseConvertedSubtitleURLs()
        bridge?.setPaused(true)
        bridge?.stop()
        currentTime = 0
        duration = 0
        onPausedChanged?(true)
        onTimeChanged?(0, 0)
    }

    func cycleAudioTrack() {
        bridge?.cycleAudioTrack()
    }

    func cycleSubtitleTrack() {
        bridge?.cycleSubtitleTrack()
    }

    func addSubtitle(url: URL,
                     fallbackURLs: [URL] = [],
                     title: String? = nil,
                     headers: [String: String] = [:],
                     convertTraditionalChinese: Bool = false,
                     sourceCodec: String? = nil,
                     isTextSubtitle: Bool? = nil,
                     fallbackToOriginal: Bool = true) {
        if url.startAccessingSecurityScopedResource() {
            scopedSubtitleURLs.append(url)
        }

        guard convertTraditionalChinese,
              MPVSubtitleFileConverter.canConvert(url: url, codec: sourceCodec, isTextSubtitle: isTextSubtitle)
        else {
            if fallbackToOriginal {
                bridge?.addSubtitleURL(url, title: title)
            }
            return
        }

        let generation = subtitleLoadGeneration
        let candidateURLs = [url] + fallbackURLs
        DispatchQueue.global(qos: .userInitiated).async {
            let convertedURL = MPVSubtitleFileConverter.convertedSubtitleURL(for: candidateURLs,
                                                                             headers: headers,
                                                                             codec: sourceCodec,
                                                                             isTextSubtitle: isTextSubtitle)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.subtitleLoadGeneration == generation else {
                    if let convertedURL {
                        try? FileManager.default.removeItem(at: convertedURL)
                    }
                    return
                }

                if let convertedURL {
                    self.convertedSubtitleURLs.append(convertedURL)
                    self.bridge?.addSubtitleURL(convertedURL, title: title)
                } else if fallbackToOriginal {
                    self.bridge?.addSubtitleURL(url, title: title)
                }
            }
        }
    }

    func selectAudioTrack(id: String) {
        bridge?.selectAudioTrackID(id)
    }

    func selectSubtitleTrack(id: String) {
        bridge?.selectSubtitleTrackID(id)
    }

    func disableSubtitle() {
        bridge?.disableSubtitle()
    }

    func logPerformanceSnapshot(reason: String) {
        bridge?.logPerformanceSnapshot(withReason: reason)
    }

    func shutdown() {
        bridge?.shutdown()
        bridge = nil
        releaseScopedURL()
        releaseScopedSubtitleURLs()
        releaseConvertedSubtitleURLs()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
        } catch {
            try session.setCategory(.playback, mode: .default)
        }
        try session.setActive(true)
    }

    private func releaseScopedURL() {
        if scopedAccess {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        scopedAccess = false
    }

    private func releaseScopedSubtitleURLs() {
        scopedSubtitleURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedSubtitleURLs.removeAll()
    }

    private func releaseConvertedSubtitleURLs() {
        convertedSubtitleURLs.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        convertedSubtitleURLs.removeAll()
    }
}

extension MPVPlayerController: MPVClientBridgeDelegate {
    func mpvClientDidUpdateTime(_ time: Double, duration: Double) {
        currentTime = time.isFinite ? time : 0
        self.duration = duration.isFinite ? duration : 0
        onTimeChanged?(currentTime, self.duration)
    }

    func mpvClientDidUpdatePaused(_ paused: Bool) {
        isPaused = paused
        onPausedChanged?(paused)
    }

    func mpvClientDidUpdateBuffering(_ buffering: Bool) {
        isBuffering = buffering
        onBufferingChanged?(buffering)
    }

    func mpvClientDidUpdateVideoRectWith(x: Double,
                                         y: Double,
                                         width: Double,
                                         height: Double,
                                         osdWidth: Double,
                                         osdHeight: Double,
                                         marginLeft: Double,
                                         marginRight: Double,
                                         marginTop: Double,
                                         marginBottom: Double) {
        let rect = MPVVideoRect(x: x,
                                y: y,
                                width: width,
                                height: height,
                                osdWidth: osdWidth,
                                osdHeight: osdHeight,
                                marginLeft: marginLeft,
                                marginRight: marginRight,
                                marginTop: marginTop,
                                marginBottom: marginBottom)
        onVideoRectChanged?(rect)
    }

    func mpvClientDidRenderFirstFrame() {
        onFirstFrameRendered?()
    }

    func mpvClientDidFinishPlayback() {
        onFinished?()
    }

    func mpvClientDidFail(withMessage message: String) {
        onError?(message)
    }

    func mpvClientDidLog(_ message: String) {
        onLog?(message)
    }

    func mpvClientDidUpdateSubtitleTracks(_ tracks: [[String: Any]], selectedID: String?) {
        let subtitleTracks = tracks.compactMap { item -> MPVSubtitleTrack? in
            guard let id = item["id"] as? String else { return nil }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "字幕 \(id)"
            let selected = (item["selected"] as? Bool) ?? (id == selectedID)
            let language = (item["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let codec = (item["codec"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let external = (item["external"] as? Bool) ?? false
            return MPVSubtitleTrack(id: id,
                                    title: title,
                                    isSelected: selected,
                                    language: language,
                                    codec: codec,
                                    isExternal: external)
        }
        onSubtitleTracksChanged?(subtitleTracks, selectedID)
    }

    func mpvClientDidUpdateSubtitleText(_ text: String?) {
        onSubtitleTextChanged?(text)
    }
}
