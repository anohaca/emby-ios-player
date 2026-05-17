//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG

import Defaults
import Factory
import SwiftUI
import UIKit

struct DebugCompatibilitySmokeView: View {

    @StateObject
    private var runner = DebugCompatibilitySmokeRunner()

    var body: some View {
        ZStack(alignment: .topLeading) {
            DebugCompatibilityPlayerView(runner: runner)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(runner.stateTitle)
                    .font(.headline.monospacedDigit())

                Text(runner.stateDetail)
                    .font(.caption.monospaced())
                    .lineLimit(8)

                Text(runner.summaryLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
            .padding(.top, 18)
            .padding(.leading, 18)
        }
        .background(Color.black)
        .statusBarHidden(true)
        .task {
            await runner.run()
        }
    }
}

private struct DebugCompatibilityPlayerView: UIViewRepresentable {

    let runner: DebugCompatibilitySmokeRunner

    func makeUIView(context: Context) -> MPVPlayerView {
        let view = MPVPlayerView()
        view.onReadyForRendering = { playerView in
            Task { @MainActor in
                runner.playerViewReady(playerView)
            }
        }
        return view
    }

    func updateUIView(_ uiView: MPVPlayerView, context: Context) {}
}

@MainActor
final class DebugCompatibilitySmokeRunner: ObservableObject {

    @Published
    var stateTitle = "COMPATIBILITY_SMOKE"

    @Published
    var stateDetail = "Waiting for player view"

    @Published
    var summaryLine = "0/0"

    private struct Configuration {
        let mediaDirectoryName: String
        let secondsPerCase: TimeInterval
        let settleSeconds: TimeInterval
        let maxCases: Int?
        let embyScanLimit: Int
        let mpvLogLevel: String
        let source: Source
        let exportEmbySession: Bool
        let embySessionFileName: String
        let explicitEmbySession: PortableEmbySession?
        let explicitEmbyItemIDs: [String]
        let startSeconds: Double

        enum Source: String {
            case emby
            case local
        }

        static var current: Configuration {
            let arguments = ProcessInfo.processInfo.arguments
            let seconds = arguments.double(after: "-EmbyCompatibilitySmokeSeconds") ?? 12
            let settle = arguments.double(after: "-EmbyCompatibilitySmokeSettleSeconds") ?? 1.5
            let maxCases = arguments.int(after: "-EmbyCompatibilitySmokeMaxCases")
            let source = Source(rawValue: arguments.value(after: "-EmbyCompatibilitySmokeSource") ?? "") ?? .local
            let sessionFileName = arguments.value(after: "-EmbyCompatibilitySmokeSessionFile") ?? "compatibility-emby-session.json"
            let itemIDs = arguments.value(after: "-EmbyCompatibilitySmokeItemIDs")?
                .split(whereSeparator: { ",; ".contains($0) })
                .map(String.init) ?? []
            return Configuration(
                mediaDirectoryName: arguments.value(after: "-EmbyCompatibilitySmokeDirectory") ?? "CompatibilityMedia",
                secondsPerCase: max(4, seconds),
                settleSeconds: max(0.5, settle),
                maxCases: maxCases.map { max(1, $0) },
                embyScanLimit: max(1, arguments.int(after: "-EmbyCompatibilitySmokeEmbyScanLimit") ?? 800),
                mpvLogLevel: arguments.value(after: "-EmbyCompatibilitySmokeMPVLogLevel") ?? "info",
                source: source,
                exportEmbySession: arguments.contains("-EmbyCompatibilitySmokeExportEmbySession"),
                embySessionFileName: sessionFileName,
                explicitEmbySession: PortableEmbySession(arguments: arguments),
                explicitEmbyItemIDs: itemIDs,
                startSeconds: max(0, arguments.double(after: "-EmbyCompatibilitySmokeStartSeconds") ?? 0)
            )
        }
    }

    private struct PortableEmbySession: Codable {
        let serverID: String
        let serverName: String
        let serverURL: String
        let userID: String
        let username: String
        let accessToken: String

        init(
            serverID: String,
            serverName: String,
            serverURL: String,
            userID: String,
            username: String,
            accessToken: String
        ) {
            self.serverID = serverID
            self.serverName = serverName
            self.serverURL = serverURL
            self.userID = userID
            self.username = username
            self.accessToken = accessToken
        }

        init?(arguments: [String]) {
            guard let serverURL = arguments.value(after: "-EmbyCompatibilitySmokeServerURL"),
                  let userID = arguments.value(after: "-EmbyCompatibilitySmokeUserID"),
                  let accessToken = arguments.value(after: "-EmbyCompatibilitySmokeAccessToken"),
                  !serverURL.isEmpty,
                  !userID.isEmpty,
                  !accessToken.isEmpty
            else { return nil }

            self.serverURL = serverURL
            self.userID = userID
            self.accessToken = accessToken
            self.serverID = arguments.value(after: "-EmbyCompatibilitySmokeServerID") ?? serverURL
            self.serverName = arguments.value(after: "-EmbyCompatibilitySmokeServerName") ?? "Emby"
            self.username = arguments.value(after: "-EmbyCompatibilitySmokeUsername") ?? userID
        }
    }

    private struct SubtitleCase {
        let url: URL
        let title: String?
    }

    private struct MediaCase {
        let index: Int
        let url: URL
        let headers: [String: String]
        let startSeconds: Double
        let subtitleURLs: [SubtitleCase]
        let displayName: String
        let source: String
        let itemID: String?
        let title: String?
        let container: String?
        let mediaSourceID: String?
        let videoCodec: String?
        let videoProfile: String?
        let videoPixelFormat: String?
        let videoSize: String?
        let audioCodecs: [String]
        let subtitleCodecs: [String]
        let expectedSizeBytes: Int64?
        let directPlay: Bool?
        let transcoding: Bool?
    }

    private struct Report: Codable {
        let device: String
        let systemVersion: String
        let appVersion: String
        let startedAt: String
        let finishedAt: String
        let mediaDirectory: String
        let secondsPerCase: Double
        let total: Int
        let passed: Int
        let failed: Int
        let cases: [CaseReport]
    }

    private struct CaseReport: Codable {
        let index: Int
        let fileName: String
        let fileExtension: String
        let fileSizeBytes: Int64
        let source: String
        let itemID: String?
        let title: String?
        let container: String?
        let mediaSourceID: String?
        let videoCodec: String?
        let videoProfile: String?
        let videoPixelFormat: String?
        let videoSize: String?
        let audioCodecs: [String]
        let subtitleCodecs: [String]
        let directPlay: Bool?
        let transcoding: Bool?
        let subtitleFiles: [String]
        let loaded: Bool
        let progressed: Bool
        let finished: Bool
        let duration: Double
        let maxTime: Double
        let firstProgressSeconds: Double?
        let subtitleTrackCount: Int
        let selectedSubtitleID: String?
        let sawSubtitleText: Bool
        let subtitleTextSamples: [String]
        let lastVideoRect: VideoRectReport?
        let diagnostics: DiagnosticsReport
        let errors: [String]
        let passed: Bool
        let notes: [String]
    }

    private struct VideoRectReport: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let osdWidth: Double
        let osdHeight: Double
    }

    private struct DiagnosticsReport: Codable {
        let currentVO: String?
        let currentGPUContext: String?
        let hwdecCurrent: String?
        let hwdecInterop: String?
        let videoParams: String?
        let videoOutParams: String?
        let audioOutParams: String?
        let performanceSamples: [String]
        let subtitleDisplaySamples: [String]
        let tailLog: [String]
    }

    private struct MutableCaseState {
        var loaded = false
        var finished = false
        var duration = 0.0
        var maxTime = 0.0
        var firstProgressSeconds: Double?
        var caseStartedAt = Date()
        var subtitleTracks: [MPVSubtitleTrack] = []
        var maxSubtitleTrackCount = 0
        var selectedSubtitleID: String?
        var subtitleTextSamples: [String] = []
        var lastVideoRect: MPVVideoRect?
        var errors: [String] = []
        var logs: [String] = []
    }

    private let configuration = Configuration.current
    private let controller = MPVPlayerController()
    private var playerView: MPVPlayerView?
    private var readyContinuation: CheckedContinuation<MPVPlayerView, Never>?
    private var hasRun = false
    private var caseState = MutableCaseState()
    private let startDate = Date()

    func playerViewReady(_ playerView: MPVPlayerView) {
        if self.playerView == nil {
            self.playerView = playerView
        }
        readyContinuation?.resume(returning: playerView)
        readyContinuation = nil
    }

    func run() async {
        guard !hasRun else { return }
        hasRun = true

        setenv("LIBMPVPLAYER_SMOKE_LOG", "1", 1)
        setenv("LIBMPVPLAYER_MPV_LOG_LEVEL", configuration.mpvLogLevel, 1)
        setenv("LIBMPVPLAYER_SUBTITLE_DIAGNOSTICS", "1", 1)
        clearPreviousRunArtifacts()
        writeRunState("started source=\(configuration.source.rawValue) seconds=\(configuration.secondsPerCase) maxCases=\(configuration.maxCases.map(String.init) ?? "<default>")")

        let mediaDirectory = Self.documentsDirectory
            .appendingPathComponent(configuration.mediaDirectoryName, isDirectory: true)

        do {
            try await EmbyStore.setupDataStack()

            if configuration.exportEmbySession {
                let exportURL = try exportCurrentEmbySession()
                stateTitle = "COMPATIBILITY_SMOKE_SESSION_EXPORTED"
                stateDetail = "Session: \(exportURL.path)"
                writeRunState("exported_session file=\(exportURL.lastPathComponent)")
                NSLog("COMPATIBILITY_SMOKE_SESSION_EXPORTED %@", exportURL.path)
                return
            }

            stateTitle = "COMPATIBILITY_SMOKE_RUNNING"
            stateDetail = "Waiting for render layer"
            let view = await waitForPlayerView()

            configureCallbacks()
            try controller.attach(to: view)

            let cases = try await discoverCases(in: mediaDirectory)
            guard !cases.isEmpty else {
                throw DebugCompatibilitySmokeError("No media cases for \(configuration.source.rawValue)")
            }

            summaryLine = "0/\(cases.count)"
            var reports: [CaseReport] = []
            reports.reserveCapacity(cases.count)

            for mediaCase in cases {
                let report = await run(mediaCase)
                reports.append(report)
                let passedCount = reports.filter(\.passed).count
                summaryLine = "\(reports.count)/\(cases.count) pass=\(passedCount) fail=\(reports.count - passedCount)"
            }

            controller.shutdown()

            let passedCount = reports.filter(\.passed).count
            let report = Report(
                device: UIDevice.current.model,
                systemVersion: UIDevice.current.systemVersion,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                startedAt: Self.iso8601.string(from: startDate),
                finishedAt: Self.iso8601.string(from: Date()),
                mediaDirectory: configuration.source == .emby ? "emby://\(Container.shared.currentUserSession()?.server.name ?? "current-library")" : mediaDirectory.path,
                secondsPerCase: configuration.secondsPerCase,
                total: reports.count,
                passed: passedCount,
                failed: reports.count - passedCount,
                cases: reports
            )
            let reportURL = try write(report)

            stateTitle = passedCount == reports.count ? "COMPATIBILITY_SMOKE_PASS" : "COMPATIBILITY_SMOKE_DONE_WITH_FAILURES"
            stateDetail = "Report: \(reportURL.path)"
            NSLog("COMPATIBILITY_SMOKE_REPORT %@", reportURL.path)
        } catch {
            controller.shutdown()
            stateTitle = "COMPATIBILITY_SMOKE_FAIL"
            stateDetail = error.localizedDescription
            writeRunState("failed source=\(configuration.source.rawValue) error=\(error.localizedDescription)")
            writeError(error)
            NSLog("COMPATIBILITY_SMOKE_FAIL %@", error.localizedDescription)
        }
    }

    private func waitForPlayerView() async -> MPVPlayerView {
        if let playerView {
            return playerView
        }

        return await withCheckedContinuation { continuation in
            readyContinuation = continuation
        }
    }

    private func configureCallbacks() {
        controller.onTimeChanged = { [weak self] time, duration in
            Task { @MainActor in
                guard let self else { return }
                if duration.isFinite, duration > 0 {
                    self.caseState.duration = duration
                }
                if time.isFinite {
                    self.caseState.maxTime = max(self.caseState.maxTime, time)
                    if time >= 0.75, self.caseState.firstProgressSeconds == nil {
                        self.caseState.firstProgressSeconds = Date().timeIntervalSince(self.caseState.caseStartedAt)
                    }
                }
            }
        }

        controller.onVideoRectChanged = { [weak self] rect in
            Task { @MainActor in
                self?.caseState.lastVideoRect = rect
            }
        }

        controller.onFinished = { [weak self] in
            Task { @MainActor in
                self?.caseState.finished = true
            }
        }

        controller.onError = { [weak self] message in
            Task { @MainActor in
                self?.caseState.errors.append(message)
            }
        }

        controller.onLog = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.caseState.logs.append(message)
                if self.caseState.logs.count > 240 {
                    self.caseState.logs.removeFirst(self.caseState.logs.count - 240)
                }
                if message.contains("mpv-event name=file-loaded") {
                    self.caseState.loaded = true
                }
            }
        }

        controller.onSubtitleTracksChanged = { [weak self] tracks, selectedID in
            Task { @MainActor in
                self?.caseState.subtitleTracks = tracks
                self?.caseState.maxSubtitleTrackCount = max(self?.caseState.maxSubtitleTrackCount ?? 0, tracks.count)
                if let selectedID {
                    self?.caseState.selectedSubtitleID = selectedID
                }
            }
        }

        controller.onSubtitleTextChanged = { [weak self] text in
            Task { @MainActor in
                guard let self,
                      let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return }
                if !self.caseState.subtitleTextSamples.contains(text) {
                    self.caseState.subtitleTextSamples.append(text)
                    if self.caseState.subtitleTextSamples.count > 5 {
                        self.caseState.subtitleTextSamples.removeFirst(self.caseState.subtitleTextSamples.count - 5)
                    }
                }
            }
        }
    }

    private func discoverCases(in directory: URL) async throws -> [MediaCase] {
        switch configuration.source {
        case .emby:
            return try await discoverEmbyCases()
        case .local:
            return try discoverLocalCases(in: directory)
        }
    }

    private func discoverLocalCases(in directory: URL) throws -> [MediaCase] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            throw DebugCompatibilitySmokeError("Missing media directory \(directory.path)")
        }

        let mediaExtensions: Set<String> = [
            "3gp",
            "avi",
            "flv",
            "m2ts",
            "m4v",
            "mkv",
            "mov",
            "mp4",
            "mpeg",
            "mpg",
            "mts",
            "ogv",
            "rm",
            "rmvb",
            "ts",
            "vob",
            "webm",
            "wmv",
        ]

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var mediaURLs = urls.filter { url in
            mediaExtensions.contains(url.pathExtension.lowercased()) &&
                !url.lastPathComponent.hasPrefix("._")
        }
        mediaURLs.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        if let maxCases = configuration.maxCases, mediaURLs.count > maxCases {
            mediaURLs = Array(mediaURLs.prefix(maxCases))
        }

        return mediaURLs.enumerated().map { offset, mediaURL in
            let subtitles = ((try? MPVSubtitleAutoLoader.matchingSubtitleURLs(for: mediaURL)) ?? [])
                .map { SubtitleCase(url: $0, title: $0.lastPathComponent) }
            return MediaCase(
                index: offset + 1,
                url: mediaURL,
                headers: [:],
                startSeconds: configuration.startSeconds,
                subtitleURLs: subtitles,
                displayName: mediaURL.lastPathComponent,
                source: "local",
                itemID: nil,
                title: nil,
                container: mediaURL.pathExtension.lowercased(),
                mediaSourceID: nil,
                videoCodec: nil,
                videoProfile: nil,
                videoPixelFormat: nil,
                videoSize: nil,
                audioCodecs: [],
                subtitleCodecs: subtitles.map { $0.url.pathExtension.lowercased() },
                expectedSizeBytes: nil,
                directPlay: nil,
                transcoding: nil
            )
        }
    }

    private func discoverEmbyCases() async throws -> [MediaCase] {
        let userSession = try resolveEmbyUserSession()

        stateDetail = "Scanning Emby media library"
        let selectedItems: [BaseItemDto]
        if configuration.explicitEmbyItemIDs.isEmpty {
            let items = try await fetchEmbyVideoItems(userSession: userSession)
            selectedItems = selectDiverseEmbyItems(items)
        } else {
            selectedItems = try await fetchExplicitEmbyVideoItems(
                itemIDs: configuration.explicitEmbyItemIDs,
                userSession: userSession
            )
        }

        var cases: [MediaCase] = []
        cases.reserveCapacity(selectedItems.count)
        for item in selectedItems {
            do {
                let playbackItem = try await MediaPlayerItem.build(
                    for: item,
                    compatibilityMode: .directPlay
                )
                cases.append(makeEmbyCase(
                    index: cases.count + 1,
                    playbackItem: playbackItem,
                    userSession: userSession
                ))
            } catch {
                NSLog("COMPATIBILITY_SMOKE_EMBY_SKIP item=%@ error=%@",
                      item.id ?? "<nil>",
                      error.localizedDescription)
            }
        }

        return cases
    }

    private func fetchExplicitEmbyVideoItems(
        itemIDs: [String],
        userSession: UserSession
    ) async throws -> [BaseItemDto] {
        var items: [BaseItemDto] = []
        items.reserveCapacity(itemIDs.count)

        for itemID in itemIDs {
            let item: BaseItemDto = try await userSession.embyClient.item(
                itemID: itemID,
                as: BaseItemDto.self
            )
            guard item.isPlayable else {
                NSLog("COMPATIBILITY_SMOKE_EMBY_SKIP item=%@ error=not-playable", itemID)
                continue
            }
            items.append(item)
        }

        return items
    }

    private func resolveEmbyUserSession() throws -> UserSession {
        if let explicitSession = configuration.explicitEmbySession {
            return try installPortableEmbySession(explicitSession)
        }

        if let userSession = Container.shared.currentUserSession() {
            return userSession
        }

        if let portableSession = try loadPortableEmbySessionIfAvailable() {
            return try installPortableEmbySession(portableSession)
        }

        throw DebugCompatibilitySmokeError("No signed-in Emby user session")
    }

    private func exportCurrentEmbySession() throws -> URL {
        guard let userSession = Container.shared.currentUserSession() else {
            throw DebugCompatibilitySmokeError("No signed-in Emby user session to export")
        }

        let session = PortableEmbySession(
            serverID: userSession.server.id,
            serverName: userSession.server.name,
            serverURL: userSession.server.currentURL.absoluteString,
            userID: userSession.user.id,
            username: userSession.user.username,
            accessToken: userSession.embyClient.configuration.accessToken
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        let url = Self.documentsDirectory.appendingPathComponent(configuration.embySessionFileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func loadPortableEmbySessionIfAvailable() throws -> PortableEmbySession? {
        let url = Self.documentsDirectory.appendingPathComponent(configuration.embySessionFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PortableEmbySession.self, from: data)
    }

    private func installPortableEmbySession(_ portableSession: PortableEmbySession) throws -> UserSession {
        guard let serverURL = URL(string: portableSession.serverURL) else {
            throw DebugCompatibilitySmokeError("Invalid Emby server URL")
        }

        let server = ServerState(
            urls: [serverURL],
            currentURL: serverURL,
            name: portableSession.serverName,
            id: portableSession.serverID,
            userIDs: [portableSession.userID]
        )
        let user = UserState(
            id: portableSession.userID,
            serverID: server.id,
            username: portableSession.username
        )

        var servers = StoredValues[.Server.servers]
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        StoredValues[.Server.servers] = servers

        var users = StoredValues[.User.users]
        users.removeAll { $0.id == user.id }
        users.append(user)
        StoredValues[.User.users] = users

        guard user.storeAccessToken(portableSession.accessToken) else {
            throw DebugCompatibilitySmokeError("Failed to save Emby access token")
        }

        var userData = UserDto()
        userData.id = user.id
        userData.name = user.username
        user.data = userData

        Defaults[.selectUserServerSelection] = .server(id: server.id)
        Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
        Container.shared.currentUserSession.reset()

        guard let userSession = Container.shared.currentUserSession() else {
            throw DebugCompatibilitySmokeError("Failed to create Emby user session")
        }
        return userSession
    }

    private func fetchEmbyVideoItems(userSession: UserSession) async throws -> [BaseItemDto] {
        var items: [BaseItemDto] = []
        let pageSize = min(200, configuration.embyScanLimit)
        var startIndex = 0

        while items.count < configuration.embyScanLimit {
            var parameters = EmbyPortItemsParameters()
            parameters.enableUserData = true
            parameters.fields = [
                .mediaSources,
                .mediaStreams,
                .path,
                .width,
                .height,
                .etag,
            ]
            parameters.includeItemTypes = [.movie, .episode, .video]
            parameters.isRecursive = true
            parameters.limit = min(pageSize, configuration.embyScanLimit - items.count)
            parameters.sortBy = [.sortName]
            parameters.sortOrder = [.ascending]
            parameters.startIndex = startIndex

            let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
                parameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )
            let page = response.items ?? []
            items.append(contentsOf: page)
            if page.count < pageSize || items.count >= (response.totalRecordCount ?? Int.max) {
                break
            }
            startIndex += page.count
        }

        return items.filter { item in
            guard item.id?.isEmpty == false, item.isPlayable else { return false }
            return item.mediaSources?.isEmpty == false || item.mediaStreams?.isEmpty == false
        }
    }

    private func selectDiverseEmbyItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
        let targetCount = configuration.maxCases ?? 24
        guard targetCount > 0 else { return [] }

        let candidates = items.map(EmbyLibraryCandidate.init)
        var selected: [EmbyLibraryCandidate] = []
        var selectedIDs: Set<String> = []
        var selectedSignatures: Set<String> = []

        func append(_ candidate: EmbyLibraryCandidate) {
            guard selected.count < targetCount,
                  let id = candidate.item.id,
                  selectedIDs.insert(id).inserted
            else { return }
            selected.append(candidate)
            selectedSignatures.insert(candidate.compatibilitySignature)
        }

        let preferredContainers = [
            "mp4", "mkv", "avi", "mov", "m4v", "ts", "m2ts", "mts",
            "wmv", "rmvb", "rm", "mpg", "mpeg", "webm", "flv", "3gp", "ogv", "vob",
        ]
        for container in preferredContainers {
            if let candidate = candidates.first(where: { $0.containerTokens.contains(container) }) {
                append(candidate)
            }
        }

        for candidate in candidates where selected.count < targetCount {
            guard !candidate.videoCodec.isEmpty else { continue }
            if !selected.contains(where: { $0.videoCodec == candidate.videoCodec }) {
                append(candidate)
            }
        }

        for candidate in candidates where selected.count < targetCount {
            let subtitleKey = candidate.subtitleCodecs.joined(separator: ",")
            guard !subtitleKey.isEmpty else { continue }
            if !selected.contains(where: { $0.subtitleCodecs.joined(separator: ",") == subtitleKey }) {
                append(candidate)
            }
        }

        for candidate in candidates where selected.count < targetCount {
            let audioKey = candidate.audioCodecs.joined(separator: ",")
            guard !audioKey.isEmpty else { continue }
            if !selected.contains(where: { $0.audioCodecs.joined(separator: ",") == audioKey }) {
                append(candidate)
            }
        }

        for candidate in candidates where selected.count < targetCount {
            if !selectedSignatures.contains(candidate.compatibilitySignature) {
                append(candidate)
            }
        }

        for candidate in candidates where selected.count < targetCount {
            append(candidate)
        }

        return selected.map(\.item)
    }

    private func makeEmbyCase(
        index: Int,
        playbackItem: MediaPlayerItem,
        userSession: UserSession
    ) -> MediaCase {
        let mediaSource = playbackItem.mediaSource
        let videoStream = playbackItem.videoStreams.first
        let audioCodecs = uniqueLowercased(playbackItem.audioStreams.compactMap(\.codec))
        let subtitleCodecs = uniqueLowercased(playbackItem.subtitleStreams.compactMap(\.codec))
        let subtitles = playbackItem.subtitleStreams.compactMap { stream -> SubtitleCase? in
            guard isExternalSubtitle(stream),
                  let deliveryURL = stream.deliveryURL,
                  let url = userSession.embyClient.absoluteURL(forPathOrURL: deliveryURL)
            else { return nil }
            return SubtitleCase(url: url, title: externalSubtitleTitle(for: stream, url: url))
        }

        return MediaCase(
            index: index,
            url: playbackItem.url,
            headers: playbackItem.httpHeaders,
            startSeconds: configuration.startSeconds,
            subtitleURLs: subtitles,
            displayName: playbackItem.baseItem.displayTitle,
            source: "emby",
            itemID: playbackItem.baseItem.id,
            title: playbackItem.baseItem.displayTitle,
            container: mediaSource.container ?? playbackItem.baseItem.container,
            mediaSourceID: mediaSource.id,
            videoCodec: videoStream?.codec?.lowercased(),
            videoProfile: videoStream?.profile,
            videoPixelFormat: videoStream?.pixelFormat,
            videoSize: videoStream.map { stream in
                "\(stream.width ?? 0)x\(stream.height ?? 0)"
            },
            audioCodecs: audioCodecs,
            subtitleCodecs: subtitleCodecs,
            expectedSizeBytes: mediaSource.size.map(Int64.init),
            directPlay: mediaSource.transcodingURL == nil,
            transcoding: mediaSource.transcodingURL != nil
        )
    }

    private func uniqueLowercased(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private func isExternalSubtitle(_ stream: MediaStream) -> Bool {
        stream.deliveryMethod == .external ||
            stream.isExternal == true ||
            stream.deliveryURL?.isEmpty == false
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

    private func run(_ mediaCase: MediaCase) async -> CaseReport {
        caseState = MutableCaseState()
        caseState.caseStartedAt = Date()
        let fileName = mediaCase.displayName
        stateTitle = "COMPATIBILITY_SMOKE_RUNNING"
        stateDetail = "\(mediaCase.index): \(fileName)"
        NSLog("COMPATIBILITY_SMOKE_CASE_START %d %@", mediaCase.index, fileName)

        controller.load(url: mediaCase.url, headers: mediaCase.headers, startSeconds: mediaCase.startSeconds)
        for subtitle in mediaCase.subtitleURLs {
            controller.addSubtitle(url: subtitle.url, title: subtitle.title ?? subtitle.url.lastPathComponent)
        }

        try? await Task.sleep(for: .seconds(configuration.settleSeconds))
        controller.refreshVideoRect()

        let started = Date()
        var sampleIndex = 0
        while Date().timeIntervalSince(started) < configuration.secondsPerCase {
            sampleIndex += 1
            controller.logPerformanceSnapshot(reason: "compat-\(mediaCase.index)-\(sampleIndex)")
            controller.refreshVideoRect()
            try? await Task.sleep(for: .seconds(1))

            if caseState.finished, caseState.maxTime > 0 {
                break
            }
        }

        controller.logPerformanceSnapshot(reason: "compat-\(mediaCase.index)-final")
        let report = makeReport(for: mediaCase)
        controller.stop()
        try? await Task.sleep(for: .milliseconds(350))

        NSLog("COMPATIBILITY_SMOKE_CASE_%@ %d %@ time=%.3f duration=%.3f subtitles=%d errors=%d",
              report.passed ? "PASS" : "FAIL",
              mediaCase.index,
              fileName,
              report.maxTime,
              report.duration,
              report.subtitleTrackCount,
              report.errors.count)

        return report
    }

    private func makeReport(for mediaCase: MediaCase) -> CaseReport {
        let fileSize = mediaCase.expectedSizeBytes ??
            (try? mediaCase.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ??
            0
        let state = caseState
        let progressed = state.maxTime >= 1.0 || (state.finished && state.maxTime > 0.1)
        let hasVideoRect = (state.lastVideoRect?.width ?? 0) > 0 && (state.lastVideoRect?.height ?? 0) > 0
        let fatalLogs = state.logs.filter { line in
            line.localizedCaseInsensitiveContains("libmpv level=error") ||
                (line.contains("mpv-event name=end-file") && line.contains("reason=error")) ||
                (line.contains("file_error=") && !line.contains("file_error=success")) ||
                (line.localizedCaseInsensitiveContains("failed") && !line.localizedCaseInsensitiveContains("did not")) ||
                line.localizedCaseInsensitiveContains("no video") ||
                line.localizedCaseInsensitiveContains("could not")
        }
        let passed = state.loaded && progressed && hasVideoRect && state.errors.isEmpty

        var notes: [String] = []
        if !state.loaded {
            notes.append("mpv did not report file-loaded")
        }
        if !progressed {
            notes.append("playback time did not progress")
        }
        if !hasVideoRect {
            notes.append("video rect was not observed")
        }
        if !mediaCase.subtitleURLs.isEmpty,
           state.maxSubtitleTrackCount == 0,
           state.subtitleTextSamples.isEmpty {
            notes.append("external subtitle file existed but no subtitle track was observed")
        }
        if !fatalLogs.isEmpty {
            notes.append("diagnostic log contains possible error lines")
        }
        let sanitizedErrors = state.errors.map(redactedDiagnosticLine)
        let sanitizedFatalLogs = fatalLogs.map(redactedDiagnosticLine)

        return CaseReport(
            index: mediaCase.index,
            fileName: mediaCase.displayName,
            fileExtension: mediaCase.container ?? mediaCase.url.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            source: mediaCase.source,
            itemID: mediaCase.itemID,
            title: mediaCase.title,
            container: mediaCase.container,
            mediaSourceID: mediaCase.mediaSourceID,
            videoCodec: mediaCase.videoCodec,
            videoProfile: mediaCase.videoProfile,
            videoPixelFormat: mediaCase.videoPixelFormat,
            videoSize: mediaCase.videoSize,
            audioCodecs: mediaCase.audioCodecs,
            subtitleCodecs: mediaCase.subtitleCodecs,
            directPlay: mediaCase.directPlay,
            transcoding: mediaCase.transcoding,
            subtitleFiles: mediaCase.subtitleURLs.map { $0.title ?? $0.url.lastPathComponent },
            loaded: state.loaded,
            progressed: progressed,
            finished: state.finished,
            duration: state.duration,
            maxTime: state.maxTime,
            firstProgressSeconds: state.firstProgressSeconds,
            subtitleTrackCount: state.maxSubtitleTrackCount,
            selectedSubtitleID: state.selectedSubtitleID,
            sawSubtitleText: !state.subtitleTextSamples.isEmpty,
            subtitleTextSamples: state.subtitleTextSamples,
            lastVideoRect: state.lastVideoRect.map {
                VideoRectReport(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height,
                    osdWidth: $0.osdWidth,
                    osdHeight: $0.osdHeight
                )
            },
            diagnostics: diagnostics(from: state.logs),
            errors: Array((sanitizedErrors + sanitizedFatalLogs).suffix(12)),
            passed: passed,
            notes: notes
        )
    }

    private func diagnostics(from logs: [String]) -> DiagnosticsReport {
        let logs = logs.map(redactedDiagnosticLine)
        return DiagnosticsReport(
            currentVO: lastPerformanceValue(named: "current-vo", in: logs) ?? lastSnapshotValue(named: "current-vo", in: logs),
            currentGPUContext: lastPerformanceValue(named: "current-gpu-context", in: logs) ?? lastSnapshotValue(named: "current-gpu-context", in: logs),
            hwdecCurrent: lastPerformanceValue(named: "hwdec-current", in: logs) ?? lastSnapshotValue(named: "hwdec-current", in: logs),
            hwdecInterop: lastSnapshotValue(named: "hwdec-interop", in: logs),
            videoParams: lastSnapshotValue(named: "video-params", in: logs),
            videoOutParams: lastSnapshotValue(named: "video-out-params", in: logs),
            audioOutParams: lastSnapshotValue(named: "audio-out-params", in: logs),
            performanceSamples: Array(logs.filter { $0.hasPrefix("mpv-performance ") }.suffix(8)),
            subtitleDisplaySamples: Array(logs.filter { $0.hasPrefix("subtitle-display ") }.suffix(8)),
            tailLog: Array(logs.suffix(40))
        )
    }

    private func redactedDiagnosticLine(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: #"api_key=[^\\", }]+"#,
                with: "api_key=<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"AccessToken=[^\\", }]+"#,
                with: "AccessToken=<redacted>",
                options: .regularExpression
            )
    }

    private func lastSnapshotValue(named name: String, in logs: [String]) -> String? {
        let marker = "mpv-snapshot "
        let nameMarker = " name=\(name) "
        return logs.reversed().first { $0.hasPrefix(marker) && $0.contains(nameMarker) }
            .flatMap { line in
                guard let range = line.range(of: " value=") else { return nil }
                return String(line[range.upperBound...])
            }
    }

    private func lastPerformanceValue(named name: String, in logs: [String]) -> String? {
        let key = "\(name)="
        guard let line = logs.reversed().first(where: { $0.hasPrefix("mpv-performance ") }),
              let range = line.range(of: key)
        else { return nil }

        let tail = line[range.upperBound...]
        if let end = tail.firstIndex(of: " ") {
            return String(tail[..<end])
        }
        return String(tail)
    }

    private func write(_ report: Report) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let reportURL = Self.reportURL
        try data.write(to: reportURL, options: .atomic)
        return reportURL
    }

    private func clearPreviousRunArtifacts() {
        try? FileManager.default.removeItem(at: Self.reportURL)
        try? FileManager.default.removeItem(at: Self.errorURL)
        try? FileManager.default.removeItem(at: Self.runStateURL)
    }

    private func writeError(_ error: Error) {
        let text = [
            "source=\(configuration.source.rawValue)",
            "error=\(error.localizedDescription)",
            "date=\(Self.iso8601.string(from: Date()))",
            "arguments=\(Self.redactedArguments.joined(separator: " "))",
        ].joined(separator: "\n")
        try? text.write(to: Self.errorURL, atomically: true, encoding: .utf8)
    }

    private func writeRunState(_ state: String) {
        let text = [
            "date=\(Self.iso8601.string(from: Date()))",
            state,
            "arguments=\(Self.redactedArguments.joined(separator: " "))",
        ].joined(separator: "\n")
        try? text.write(to: Self.runStateURL, atomically: true, encoding: .utf8)
    }

    private static var redactedArguments: [String] {
        var arguments = ProcessInfo.processInfo.arguments
        let secretArguments: Set<String> = [
            "-EmbyCompatibilitySmokeAccessToken",
        ]
        for index in arguments.indices where secretArguments.contains(arguments[index]) {
            let valueIndex = arguments.index(after: index)
            if arguments.indices.contains(valueIndex) {
                arguments[valueIndex] = "<redacted>"
            }
        }
        return arguments
    }

    private static let documentsDirectory: URL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    )[0]

    private static let reportURL = documentsDirectory.appendingPathComponent("compatibility-report.json")
    private static let errorURL = documentsDirectory.appendingPathComponent("compatibility-error.txt")
    private static let runStateURL = documentsDirectory.appendingPathComponent("compatibility-run-state.txt")

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct EmbyLibraryCandidate {
    let item: BaseItemDto
    let containerTokens: Set<String>
    let videoCodec: String
    let audioCodecs: [String]
    let subtitleCodecs: [String]
    let compatibilitySignature: String

    init(item: BaseItemDto) {
        self.item = item

        let mediaSource = item.mediaSources?.first
        let streams = mediaSource?.mediaStreams ?? item.mediaStreams ?? []
        let containers = [
            mediaSource?.container,
            item.container,
        ]
            .compactMap { $0 }
            .flatMap { value in
                value
                    .lowercased()
                    .split(whereSeparator: { ",;/| ".contains($0) })
                    .map(String.init)
            }
            .filter { !$0.isEmpty }
        let resolvedContainerTokens = Set(containers)
        containerTokens = resolvedContainerTokens

        let resolvedVideoCodec = streams
            .first { $0.type == .video }?
            .codec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        videoCodec = resolvedVideoCodec

        let resolvedAudioCodecs = Self.uniqueCodecs(in: streams, type: .audio)
        let resolvedSubtitleCodecs = Self.uniqueCodecs(in: streams, type: .subtitle)
        audioCodecs = resolvedAudioCodecs
        subtitleCodecs = resolvedSubtitleCodecs
        compatibilitySignature = [
            resolvedContainerTokens.sorted().joined(separator: "+"),
            resolvedVideoCodec,
            resolvedAudioCodecs.joined(separator: "+"),
            resolvedSubtitleCodecs.joined(separator: "+"),
        ].joined(separator: "|")
    }

    private static func uniqueCodecs(in streams: [MediaStream], type: MediaStreamType) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for stream in streams where stream.type == type {
            guard let codec = stream.codec?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !codec.isEmpty,
                  seen.insert(codec).inserted
            else { continue }
            result.append(codec)
        }
        return result
    }
}

private struct DebugCompatibilitySmokeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private extension [String] {

    func value(after argument: String) -> String? {
        guard let index = firstIndex(of: argument) else { return nil }
        let valueIndex = self.index(after: index)
        guard indices.contains(valueIndex) else { return nil }
        return self[valueIndex]
    }

    func int(after argument: String) -> Int? {
        value(after: argument).flatMap(Int.init)
    }

    func double(after argument: String) -> Double? {
        value(after: argument).flatMap(Double.init)
    }
}

#endif
