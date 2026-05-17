//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct EmbyPortPlaybackRequest: Equatable, Sendable {
    var itemID: String
    var mediaSourceID: String?
    var playSessionID: String?
    var url: URL
    var headers: [String: String]
    var startSeconds: TimeInterval?

    init(
        itemID: String,
        mediaSourceID: String? = nil,
        playSessionID: String? = nil,
        url: URL,
        headers: [String: String],
        startSeconds: TimeInterval? = nil
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.url = url
        self.headers = headers
        self.startSeconds = startSeconds
    }
}

struct PlaybackStartInfo {
    var audioStreamIndex: Int?
    var itemID: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var positionTicks: Int64?
    var sessionID: String?
    var subtitleStreamIndex: Int?
}

struct PlaybackProgressInfo {
    var audioStreamIndex: Int?
    var isPaused: Bool = false
    var itemID: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var positionTicks: Int64?
    var sessionID: String?
    var subtitleStreamIndex: Int?
}

struct PlaybackStopInfo {
    var itemID: String?
    var mediaSourceID: String?
    var positionTicks: Int64?
    var sessionID: String?
}

protocol EmbyPortPlayerEngine: AnyObject {
    func load(_ request: EmbyPortPlaybackRequest) async throws
    func play() async
    func pause() async
    func seek(to seconds: TimeInterval) async
    func stop() async
}

final class EmbyPortPlaybackCoordinator {
    private let engine: EmbyPortPlayerEngine

    init(engine: EmbyPortPlayerEngine) {
        self.engine = engine
    }

    func play(_ request: EmbyPortPlaybackRequest) async throws {
        try await engine.load(request)
        await engine.play()
    }

    func pause() async {
        await engine.pause()
    }

    func seek(to seconds: TimeInterval) async {
        await engine.seek(to: max(0, seconds))
    }

    func stop() async {
        await engine.stop()
    }
}
