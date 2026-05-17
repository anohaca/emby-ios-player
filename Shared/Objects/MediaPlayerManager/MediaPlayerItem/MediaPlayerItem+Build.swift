//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation
import Logging

// TODO: build report of determined values for playback information
//       - transcode, video stream, path

extension MediaPlayerItem {

    /// The main `MediaPlayerItem` builder for normal online usage.
    static func build(
        for initialItem: BaseItemDto,
        mediaSource _initialMediaSource: MediaSourceInfo? = nil,
        selectedAudioStreamIndex: Int? = nil,
        selectedSubtitleStreamIndex: Int? = nil,
        videoPlayerType: VideoPlayerType = Defaults[.VideoPlayer.videoPlayerType],
        requestedBitrate: PlaybackBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate],
        compatibilityMode: PlaybackCompatibility = Defaults[.VideoPlayer.Playback.compatibilityMode],
        modifyItem: ((inout BaseItemDto) -> Void)? = nil
    ) async throws -> MediaPlayerItem {

        let logger = Logger.emby()

        guard let itemID = initialItem.id else {
            logger.critical("No item ID!")
            throw ErrorMessage(L10n.unknownError)
        }

        guard let userSession = Container.shared.currentUserSession() else {
            logger.critical("No user session!")
            throw ErrorMessage(L10n.unknownError)
        }

        var item = try await initialItem.getFullItem(userSession: userSession)

        if let modifyItem {
            modifyItem(&item)
        }

        #if os(iOS)
        let resolvedVideoPlayerType = VideoPlayerType.emby
        #else
        let resolvedVideoPlayerType = videoPlayerType
        #endif

        guard let initialMediaSource = {
            if let _initialMediaSource {
                return _initialMediaSource
            }

            if let first = item.mediaSources?.first {
                logger.trace("Using first media source for item \(itemID)")
                return first
            }

            return nil
        }() else {
            logger.error("No media sources for item \(itemID)!")
            throw ErrorMessage(L10n.unknownError)
        }

        let maxBitrate = try await requestedBitrate.getMaxBitrate()

        let deviceProfile = DeviceProfile.build(
            for: resolvedVideoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate
        )

        let resolvedSelectedAudioStreamIndex = selectedAudioStreamIndex ??
            MediaTrackDefaults.preferredAudioStreamIndex(in: initialMediaSource)
        let resolvedSelectedSubtitleStreamIndex = selectedSubtitleStreamIndex ??
            MediaTrackDefaults.preferredSubtitleStreamIndex(in: initialMediaSource)

        var playbackInfo = PlaybackInfoDto()
        playbackInfo.isAutoOpenLiveStream = true
        playbackInfo.deviceProfile = deviceProfile
        playbackInfo.liveStreamID = initialMediaSource.liveStreamID
        playbackInfo.maxStreamingBitrate = maxBitrate
        playbackInfo.userID = userSession.user.id
        playbackInfo.audioStreamIndex = resolvedSelectedAudioStreamIndex
        playbackInfo.subtitleStreamIndex = resolvedSelectedSubtitleStreamIndex

        if !item.isLiveStream {
            playbackInfo.mediaSourceID = initialMediaSource.id
        }

        let response: EmbyPortPlaybackInfoResponse = try await userSession.embyClient.send(
            path: "/Items/\(itemID)/PlaybackInfo",
            method: "POST",
            body: playbackInfo
        )

        let mediaSource: MediaSourceInfo? = {

            guard let mediaSources = response.mediaSources else { return nil }

            if let matchingTag = mediaSources.first(where: { $0.eTag == initialMediaSource.eTag }) {
                return matchingTag
            }

            for source in mediaSources {
                if let openToken = source.openToken,
                   let id = source.id,
                   openToken.contains(id)
                {
                    return source
                }
            }

            if let initialID = initialMediaSource.id,
               let matchingMediaSource = mediaSources.first(where: { $0.id == initialID })
            {
                return matchingMediaSource
            }

            logger.warning("Unable to find matching media source, defaulting to first media source")

            return mediaSources.first
        }()

        guard var mediaSource else {
            throw ErrorMessage("Unable to find media source for item")
        }

        if let resolvedSelectedAudioStreamIndex {
            mediaSource.defaultAudioStreamIndex = resolvedSelectedAudioStreamIndex
        }
        if let resolvedSelectedSubtitleStreamIndex {
            mediaSource.defaultSubtitleStreamIndex = resolvedSelectedSubtitleStreamIndex
        }

        guard let playSessionID = response.playSessionID else {
            throw ErrorMessage("No associated play session ID")
        }

        let playbackURL = try Self.streamURL(
            item: item,
            mediaSource: mediaSource,
            playSessionID: playSessionID,
            userSession: userSession,
            logger: logger
        )

        let videoStream = mediaSource.mediaStreams?.first { $0.type == .video }
        let audioCount = mediaSource.mediaStreams?.filter { $0.type == .audio }.count ?? 0
        let subtitleCount = mediaSource.mediaStreams?.filter { $0.type == .subtitle }.count ?? 0
        logger.info(
            """
            PLAYBACK_BUILD item=\(itemID) title=\(item.displayTitle) sourceID=\(mediaSource.id ?? "<nil>") sourceContainer=\(mediaSource.container ?? "<nil>") protocol=\(mediaSource.protocol?.rawValue ?? "<nil>") directPlay=\(mediaSource.isSupportsDirectPlay == true) directStream=\(mediaSource.isSupportsDirectStream == true) transcoding=\(mediaSource.transcodingURL != nil) urlScheme=\(playbackURL.scheme ?? "<nil>") urlPath=\(playbackURL.path) videoCodec=\(videoStream?.codec ?? "<nil>") videoProfile=\(videoStream?.profile ?? "<nil>") videoPixelFormat=\(videoStream?.pixelFormat ?? "<nil>") videoRange=\(videoStream?.videoRange?.rawValue ?? "<nil>") size=\(videoStream?.width ?? 0)x\(videoStream?.height ?? 0) audioTracks=\(audioCount) subtitleTracks=\(subtitleCount) requestedAudioIndex=\(resolvedSelectedAudioStreamIndex ?? -999) requestedSubtitleIndex=\(resolvedSelectedSubtitleStreamIndex ?? -999) mediaSourceDefaultAudioIndex=\(mediaSource.defaultAudioStreamIndex ?? -999) mediaSourceDefaultSubtitleIndex=\(mediaSource.defaultSubtitleStreamIndex ?? -999)
            """
        )

        let previewImageProvider: (any PreviewImageProvider)? = {
            let previewImageScrubbingSetting = StoredValues[.User.previewImageScrubbing]
            lazy var chapterPreviewImageProvider: ChapterPreviewImageProvider? = {
                if let chapters = item.fullChapterInfo, chapters.isNotEmpty {
                    return ChapterPreviewImageProvider(chapters: chapters)
                }
                return nil
            }()

            if case let PreviewImageScrubbingOption.trickplay(fallbackToChapters: fallbackToChapters) = previewImageScrubbingSetting {
                if let mediaSourceID = mediaSource.id,
                   let trickplayInfo = item.trickplay?[mediaSourceID]?.first
                {
                    return TrickplayPreviewImageProvider(
                        info: trickplayInfo.value,
                        itemID: itemID,
                        mediaSourceID: mediaSourceID,
                        runtime: item.runtime ?? .zero
                    )
                }

                if fallbackToChapters {
                    return chapterPreviewImageProvider
                }
            } else if previewImageScrubbingSetting == .chapters {
                return chapterPreviewImageProvider
            }

            return nil
        }()

        return .init(
            baseItem: item,
            mediaSource: mediaSource,
            playSessionID: playSessionID,
            url: playbackURL,
            httpHeaders: userSession.embyClient.playbackHeaders,
            requestedBitrate: requestedBitrate,
            previewImageProvider: previewImageProvider,
            thumbnailProvider: item.getNowPlayingImage
        )
    }

    // TODO: audio type stream
    // TODO: build live tv stream from the Emby live HLS endpoint.
    private static func streamURL(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        playSessionID: String,
        userSession: UserSession,
        logger: Logger
    ) throws -> URL {

        guard let itemID = item.id else {
            throw ErrorMessage("No item ID while building online media player item!")
        }

        if let transcodingURL = mediaSource.transcodingURL {
            logger.trace("Using transcoding URL for item \(itemID)")

            guard let fullTranscodeURL = userSession.embyClient.absoluteURL(forPathOrURL: transcodingURL)
            else { throw ErrorMessage("Unable to make transcode URL") }
            return fullTranscodeURL
        }

        if item.mediaType == .video, !item.isLiveStream {

            logger.trace("Making video stream URL for item \(itemID)")

            guard let videoStreamURL = userSession.embyClient.videoStreamURL(
                itemID: itemID,
                mediaSourceID: mediaSource.id,
                playSessionID: playSessionID,
                tag: item.etag
            )
            else { throw ErrorMessage("Unable to make video stream URL") }

            return videoStreamURL
        }

        logger.trace("Using media source path for item \(itemID)")

        guard let path = mediaSource.path, let streamURL = URL(
            string: path
        ) else { throw ErrorMessage("Unable to make stream URL") }

        return streamURL
    }
}

private struct EmbyPortPlaybackInfoResponse: Decodable {
    var mediaSources: [MediaSourceInfo]?
    var playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}
