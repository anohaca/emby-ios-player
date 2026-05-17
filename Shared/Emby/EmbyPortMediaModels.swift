//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@propertyWrapper
final class Indirect<Value: Codable & Hashable & Sendable>: Codable, Hashable, @unchecked Sendable {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    static func == (lhs: Indirect<Value>, rhs: Indirect<Value>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }

    init(from decoder: Decoder) throws {
        self.wrappedValue = try Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension KeyedDecodingContainer {

    func decode<Value>(
        _ type: Indirect<Value?>.Type,
        forKey key: Key
    ) throws -> Indirect<Value?> where Value: Codable & Hashable & Sendable {
        try decodeIfPresent(type, forKey: key) ?? Indirect<Value?>(wrappedValue: nil)
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}

struct BaseItemDto: Codable, Hashable, Identifiable, Sendable {
    var airDays: [DayOfWeek]? = nil
    var airTime: String? = nil
    var airsAfterSeasonNumber: Int? = nil
    var airsBeforeEpisodeNumber: Int? = nil
    var airsBeforeSeasonNumber: Int? = nil
    var album: String? = nil
    var albumArtist: String? = nil
    var albumArtists: [NameGuidPair]? = nil
    var albumCount: Int? = nil
    var albumID: String? = nil
    var albumPrimaryImageTag: String? = nil
    var artistCount: Int? = nil
    var artistItems: [NameGuidPair]? = nil
    var artists: [String]? = nil
    var aspectRatio: String? = nil
    var audio: ProgramAudio? = nil
    var backdropImageTags: [String]? = nil
    var canDelete: Bool? = nil
    var canDownload: Bool? = nil
    var channelID: String? = nil
    var channelName: String? = nil
    var channelNumber: String? = nil
    var channelPrimaryImageTag: String? = nil
    var channelType: ChannelType? = nil
    var chapters: [ChapterInfo]? = nil
    var childCount: Int? = nil
    var collectionType: CollectionType? = nil
    var communityRating: Float? = nil
    var completionPercentage: Double? = nil
    var container: String? = nil
    var criticRating: Float? = nil
    var cumulativeRunTimeTicks: Int? = nil
    @Indirect var currentProgram: BaseItemDto? = nil
    var customRating: String? = nil
    var dateCreated: Date? = nil
    var dateLastMediaAdded: Date? = nil
    var displayOrder: String? = nil
    var displayPreferencesID: String? = nil
    var enableMediaSourceDisplay: Bool? = nil
    var endDate: Date? = nil
    var episodeCount: Int? = nil
    var episodeTitle: String? = nil
    var etag: String? = nil
    var externalURLs: [ExternalURL]? = nil
    var extraType: ExtraType? = nil
    var forcedSortName: String? = nil
    var genreItems: [NameGuidPair]? = nil
    var genres: [String]? = nil
    var hasLyrics: Bool? = nil
    var hasSubtitles: Bool? = nil
    var height: Int? = nil
    var id: String? = nil
    var imageBlurHashes: ImageBlurHashes? = nil
    var imageOrientation: ImageOrientation? = nil
    var imageTags: [String: String]? = nil
    var indexNumber: Int? = nil
    var indexNumberEnd: Int? = nil
    var isFolder: Bool? = nil
    var isHD: Bool? = nil
    var isKids: Bool? = nil
    var isLive: Bool? = nil
    var isMovie: Bool? = nil
    var isNews: Bool? = nil
    var isPlaceHolder: Bool? = nil
    var isPremiere: Bool? = nil
    var isRepeat: Bool? = nil
    var isSeries: Bool? = nil
    var isSports: Bool? = nil
    var isoType: IsoType? = nil
    var localTrailerCount: Int? = nil
    var locationType: LocationType? = nil
    var lockData: Bool? = nil
    var lockedFields: [MetadataField]? = nil
    var mediaSourceCount: Int? = nil
    var mediaSources: [MediaSourceInfo]? = nil
    var mediaStreams: [MediaStream]? = nil
    var mediaType: MediaType? = nil
    var movieCount: Int? = nil
    var musicVideoCount: Int? = nil
    var name: String? = nil
    var normalizationGain: Float? = nil
    var number: String? = nil
    var officialRating: String? = nil
    var originalTitle: String? = nil
    var overview: String? = nil
    var parentArtImageTag: String? = nil
    var parentArtItemID: String? = nil
    var parentBackdropImageTags: [String]? = nil
    var parentBackdropItemID: String? = nil
    var parentID: String? = nil
    var parentIndexNumber: Int? = nil
    var parentLogoImageTag: String? = nil
    var parentLogoItemID: String? = nil
    var parentPrimaryImageItemID: String? = nil
    var parentPrimaryImageTag: String? = nil
    var parentThumbImageTag: String? = nil
    var parentThumbItemID: String? = nil
    var partCount: Int? = nil
    var path: String? = nil
    var people: [BaseItemPerson]? = nil
    var playAccess: PlayAccess? = nil
    var playlistItemID: String? = nil
    var preferredMetadataCountryCode: String? = nil
    var preferredMetadataLanguage: String? = nil
    var premiereDate: Date? = nil
    var primaryImageAspectRatio: Double? = nil
    var productionLocations: [String]? = nil
    var productionYear: Int? = nil
    var programCount: Int? = nil
    var programID: String? = nil
    var providerIDs: [String: String]? = nil
    var recursiveItemCount: Int? = nil
    var remoteTrailers: [MediaURL]? = nil
    var runTimeTicks: Int? = nil
    var screenshotImageTags: [String]? = nil
    var seasonID: String? = nil
    var seasonName: String? = nil
    var seriesCount: Int? = nil
    var seriesID: String? = nil
    var seriesName: String? = nil
    var seriesPrimaryImageTag: String? = nil
    var seriesStudio: String? = nil
    var seriesThumbImageTag: String? = nil
    var seriesTimerID: String? = nil
    var serverID: String? = nil
    var songCount: Int? = nil
    var sortName: String? = nil
    var sourceType: String? = nil
    var specialFeatureCount: Int? = nil
    var startDate: Date? = nil
    var status: String? = nil
    var studios: [NameGuidPair]? = nil
    var taglines: [String]? = nil
    var tags: [String]? = nil
    var timerID: String? = nil
    var trailerCount: Int? = nil
    var trickplay: [String: [String: TrickplayInfoDto]]? = nil
    var type: BaseItemKind? = nil
    var userData: UserItemDataDto? = nil
    var video3DFormat: Video3DFormat? = nil
    var videoType: VideoType? = nil
    var width: Int? = nil

    enum CodingKeys: String, CodingKey {
        case airDays = "AirDays"
        case airTime = "AirTime"
        case airsAfterSeasonNumber = "AirsAfterSeasonNumber"
        case airsBeforeEpisodeNumber = "AirsBeforeEpisodeNumber"
        case airsBeforeSeasonNumber = "AirsBeforeSeasonNumber"
        case album = "Album"
        case albumArtist = "AlbumArtist"
        case albumArtists = "AlbumArtists"
        case albumCount = "AlbumCount"
        case albumID = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case artistCount = "ArtistCount"
        case artistItems = "ArtistItems"
        case artists = "Artists"
        case aspectRatio = "AspectRatio"
        case audio = "Audio"
        case backdropImageTags = "BackdropImageTags"
        case canDelete = "CanDelete"
        case canDownload = "CanDownload"
        case channelID = "ChannelId"
        case channelName = "ChannelName"
        case channelNumber = "ChannelNumber"
        case channelPrimaryImageTag = "ChannelPrimaryImageTag"
        case channelType = "ChannelType"
        case chapters = "Chapters"
        case childCount = "ChildCount"
        case collectionType = "CollectionType"
        case communityRating = "CommunityRating"
        case completionPercentage = "CompletionPercentage"
        case container = "Container"
        case criticRating = "CriticRating"
        case cumulativeRunTimeTicks = "CumulativeRunTimeTicks"
        case currentProgram = "CurrentProgram"
        case customRating = "CustomRating"
        case dateCreated = "DateCreated"
        case dateLastMediaAdded = "DateLastMediaAdded"
        case displayOrder = "DisplayOrder"
        case displayPreferencesID = "DisplayPreferencesId"
        case enableMediaSourceDisplay = "EnableMediaSourceDisplay"
        case endDate = "EndDate"
        case episodeCount = "EpisodeCount"
        case episodeTitle = "EpisodeTitle"
        case etag = "Etag"
        case externalURLs = "ExternalUrls"
        case extraType = "ExtraType"
        case forcedSortName = "ForcedSortName"
        case genreItems = "GenreItems"
        case genres = "Genres"
        case hasLyrics = "HasLyrics"
        case hasSubtitles = "HasSubtitles"
        case height = "Height"
        case id = "Id"
        case imageBlurHashes = "ImageBlurHashes"
        case imageOrientation = "ImageOrientation"
        case imageTags = "ImageTags"
        case indexNumber = "IndexNumber"
        case indexNumberEnd = "IndexNumberEnd"
        case isFolder = "IsFolder"
        case isHD = "IsHD"
        case isKids = "IsKids"
        case isLive = "IsLive"
        case isMovie = "IsMovie"
        case isNews = "IsNews"
        case isPlaceHolder = "IsPlaceHolder"
        case isPremiere = "IsPremiere"
        case isRepeat = "IsRepeat"
        case isSeries = "IsSeries"
        case isSports = "IsSports"
        case isoType = "IsoType"
        case localTrailerCount = "LocalTrailerCount"
        case locationType = "LocationType"
        case lockData = "LockData"
        case lockedFields = "LockedFields"
        case mediaSourceCount = "MediaSourceCount"
        case mediaSources = "MediaSources"
        case mediaStreams = "MediaStreams"
        case mediaType = "MediaType"
        case movieCount = "MovieCount"
        case musicVideoCount = "MusicVideoCount"
        case name = "Name"
        case normalizationGain = "NormalizationGain"
        case number = "Number"
        case officialRating = "OfficialRating"
        case originalTitle = "OriginalTitle"
        case overview = "Overview"
        case parentArtImageTag = "ParentArtImageTag"
        case parentArtItemID = "ParentArtItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentBackdropItemID = "ParentBackdropItemId"
        case parentID = "ParentId"
        case parentIndexNumber = "ParentIndexNumber"
        case parentLogoImageTag = "ParentLogoImageTag"
        case parentLogoItemID = "ParentLogoItemId"
        case parentPrimaryImageItemID = "ParentPrimaryImageItemId"
        case parentPrimaryImageTag = "ParentPrimaryImageTag"
        case parentThumbImageTag = "ParentThumbImageTag"
        case parentThumbItemID = "ParentThumbItemId"
        case partCount = "PartCount"
        case path = "Path"
        case people = "People"
        case playAccess = "PlayAccess"
        case playlistItemID = "PlaylistItemId"
        case preferredMetadataCountryCode = "PreferredMetadataCountryCode"
        case preferredMetadataLanguage = "PreferredMetadataLanguage"
        case premiereDate = "PremiereDate"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case productionLocations = "ProductionLocations"
        case productionYear = "ProductionYear"
        case programCount = "ProgramCount"
        case programID = "ProgramId"
        case providerIDs = "ProviderIds"
        case recursiveItemCount = "RecursiveItemCount"
        case remoteTrailers = "RemoteTrailers"
        case runTimeTicks = "RunTimeTicks"
        case screenshotImageTags = "ScreenshotImageTags"
        case seasonID = "SeasonId"
        case seasonName = "SeasonName"
        case seriesCount = "SeriesCount"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case seriesStudio = "SeriesStudio"
        case seriesThumbImageTag = "SeriesThumbImageTag"
        case seriesTimerID = "SeriesTimerId"
        case serverID = "ServerId"
        case songCount = "SongCount"
        case sortName = "SortName"
        case sourceType = "SourceType"
        case specialFeatureCount = "SpecialFeatureCount"
        case startDate = "StartDate"
        case status = "Status"
        case studios = "Studios"
        case taglines = "Taglines"
        case tags = "Tags"
        case timerID = "TimerId"
        case trailerCount = "TrailerCount"
        case trickplay = "Trickplay"
        case type = "Type"
        case userData = "UserData"
        case video3DFormat = "Video3DFormat"
        case videoType = "VideoType"
        case width = "Width"
    }

    struct ImageBlurHashes: Codable, Hashable, Sendable {
        var art: [String: String]? = nil
        var backdrop: [String: String]? = nil
        var banner: [String: String]? = nil
        var box: [String: String]? = nil
        var boxRear: [String: String]? = nil
        var chapter: [String: String]? = nil
        var disc: [String: String]? = nil
        var logo: [String: String]? = nil
        var menu: [String: String]? = nil
        var primary: [String: String]? = nil
        var profile: [String: String]? = nil
        var screenshot: [String: String]? = nil
        var thumb: [String: String]? = nil

        enum CodingKeys: String, CodingKey {
            case art = "Art"
            case backdrop = "Backdrop"
            case banner = "Banner"
            case box = "Box"
            case boxRear = "BoxRear"
            case chapter = "Chapter"
            case disc = "Disc"
            case logo = "Logo"
            case menu = "Menu"
            case primary = "Primary"
            case profile = "Profile"
            case screenshot = "Screenshot"
            case thumb = "Thumb"
        }
    }
}

struct BaseItemPerson: Codable, Hashable, Identifiable, Sendable {
    var id: String? = nil
    var name: String? = nil
    var primaryImageTag: String? = nil
    var role: String? = nil
    var type: PersonKind? = nil
    var imageBlurHashes: BaseItemDto.ImageBlurHashes? = nil

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case primaryImageTag = "PrimaryImageTag"
        case role = "Role"
        case type = "Type"
        case imageBlurHashes = "ImageBlurHashes"
    }
}

struct NameGuidPair: Codable, Hashable, Identifiable, Sendable {
    var id: String? = nil
    var name: String? = nil

    init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyStringIfPresent(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

struct ExternalURL: Codable, Hashable, Sendable {
    var name: String? = nil
    var url: String? = nil

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case url = "Url"
    }
}

struct MediaURL: Codable, Hashable, Identifiable, Sendable {
    var name: String? = nil
    var url: String? = nil

    var id: Int { hashValue }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case url = "Url"
    }
}

struct ChapterInfo: Codable, Hashable, Sendable {
    var name: String? = nil
    var startPositionTicks: Int? = nil

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startPositionTicks = "StartPositionTicks"
    }
}

struct UserItemDataDto: Codable, Hashable, Sendable {
    var isFavorite: Bool? = nil
    var isLiked: Bool? = nil
    var isPlayed: Bool? = nil
    var key: String? = nil
    var lastPlayedDate: Date? = nil
    var playCount: Int? = nil
    var playbackPositionTicks: Int? = nil
    var playedPercentage: Double? = nil
    var rating: Double? = nil
    var unplayedItemCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
        case isLiked = "Likes"
        case isPlayed = "Played"
        case key = "Key"
        case lastPlayedDate = "LastPlayedDate"
        case playCount = "PlayCount"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case rating = "Rating"
        case unplayedItemCount = "UnplayedItemCount"
    }
}

struct MediaSourceInfo: Codable, Hashable, Identifiable, Sendable {
    var `protocol`: MediaProtocol? = nil
    var bitrate: Int? = nil
    var container: String? = nil
    var defaultAudioStreamIndex: Int? = nil
    var defaultSubtitleStreamIndex: Int? = nil
    var eTag: String? = nil
    var id: String? = nil
    var isRemote: Bool? = nil
    var isSupportsDirectPlay: Bool? = nil
    var isSupportsDirectStream: Bool? = nil
    var isSupportsTranscoding: Bool? = nil
    var liveStreamID: String? = nil
    var mediaStreams: [MediaStream]? = nil
    var name: String? = nil
    var openToken: String? = nil
    var path: String? = nil
    var requiredHTTPHeaders: [String: String]? = nil
    var runTimeTicks: Int? = nil
    var size: Int? = nil
    var transcodingContainer: String? = nil
    var transcodingSubProtocol: MediaStreamProtocol? = nil
    var transcodingURL: String? = nil
    var type: MediaSourceType? = nil
    var useMostCompatibleTranscodingProfile: Bool? = nil
    var video3DFormat: Video3DFormat? = nil
    var videoType: VideoType? = nil

    enum CodingKeys: String, CodingKey {
        case `protocol` = "Protocol"
        case bitrate = "Bitrate"
        case container = "Container"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
        case eTag = "ETag"
        case id = "Id"
        case isRemote = "IsRemote"
        case isSupportsDirectPlay = "SupportsDirectPlay"
        case isSupportsDirectStream = "SupportsDirectStream"
        case isSupportsTranscoding = "SupportsTranscoding"
        case liveStreamID = "LiveStreamId"
        case mediaStreams = "MediaStreams"
        case name = "Name"
        case openToken = "OpenToken"
        case path = "Path"
        case requiredHTTPHeaders = "RequiredHttpHeaders"
        case runTimeTicks = "RunTimeTicks"
        case size = "Size"
        case transcodingContainer = "TranscodingContainer"
        case transcodingSubProtocol = "TranscodingSubProtocol"
        case transcodingURL = "TranscodingUrl"
        case type = "Type"
        case useMostCompatibleTranscodingProfile = "UseMostCompatibleTranscodingProfile"
        case video3DFormat = "Video3DFormat"
        case videoType = "VideoType"
    }
}

struct PlaybackInfoDto: Codable, Hashable, Sendable {
    var audioStreamIndex: Int? = nil
    var deviceProfile: DeviceProfile? = nil
    var isAutoOpenLiveStream: Bool? = nil
    var liveStreamID: String? = nil
    var maxStreamingBitrate: Int? = nil
    var mediaSourceID: String? = nil
    var subtitleStreamIndex: Int? = nil
    var userID: String? = nil

    enum CodingKeys: String, CodingKey {
        case audioStreamIndex = "AudioStreamIndex"
        case deviceProfile = "DeviceProfile"
        case isAutoOpenLiveStream = "IsAutoOpenLiveStream"
        case liveStreamID = "LiveStreamId"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case mediaSourceID = "MediaSourceId"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case userID = "UserId"
    }
}

struct MediaStream: Codable, Hashable, Sendable {
    var aspectRatio: String? = nil
    var audioSpatialFormat: AudioSpatialFormat? = nil
    var averageFrameRate: Float? = nil
    var bitDepth: Int? = nil
    var bitRate: Int? = nil
    var channelLayout: String? = nil
    var channels: Int? = nil
    var codec: String? = nil
    var codecTag: String? = nil
    var codecTimeBase: String? = nil
    var colorPrimaries: String? = nil
    var colorRange: String? = nil
    var colorSpace: String? = nil
    var colorTransfer: String? = nil
    var deliveryMethod: SubtitleDeliveryMethod? = nil
    var deliveryURL: String? = nil
    var displayTitle: String? = nil
    var height: Int? = nil
    var index: Int? = nil
    var originalIndex: Int? = nil
    var isAVC: Bool? = nil
    var isAnamorphic: Bool? = nil
    var isDefault: Bool? = nil
    var isExternal: Bool? = nil
    var isExternalURL: Bool? = nil
    var isForced: Bool? = nil
    var isHearingImpaired: Bool? = nil
    var isInterlaced: Bool? = nil
    var isSupportsExternalStream: Bool? = nil
    var isTextSubtitleStream: Bool? = nil
    var language: String? = nil
    var level: Double? = nil
    var packetLength: Int? = nil
    var path: String? = nil
    var pixelFormat: String? = nil
    var profile: String? = nil
    var realFrameRate: Float? = nil
    var refFrames: Int? = nil
    var referenceFrameRate: Float? = nil
    var rotation: Int? = nil
    var sampleRate: Int? = nil
    var score: Int? = nil
    var timeBase: String? = nil
    var title: String? = nil
    var type: MediaStreamType? = nil
    var videoRange: VideoRange? = nil
    var videoRangeType: VideoRangeType? = nil
    var width: Int? = nil

    enum CodingKeys: String, CodingKey {
        case aspectRatio = "AspectRatio"
        case audioSpatialFormat = "AudioSpatialFormat"
        case averageFrameRate = "AverageFrameRate"
        case bitDepth = "BitDepth"
        case bitRate = "BitRate"
        case channelLayout = "ChannelLayout"
        case channels = "Channels"
        case codec = "Codec"
        case codecTag = "CodecTag"
        case codecTimeBase = "CodecTimeBase"
        case colorPrimaries = "ColorPrimaries"
        case colorRange = "ColorRange"
        case colorSpace = "ColorSpace"
        case colorTransfer = "ColorTransfer"
        case deliveryMethod = "DeliveryMethod"
        case deliveryURL = "DeliveryUrl"
        case displayTitle = "DisplayTitle"
        case height = "Height"
        case index = "Index"
        case isAVC = "IsAVC"
        case isAnamorphic = "IsAnamorphic"
        case isDefault = "IsDefault"
        case isExternal = "IsExternal"
        case isExternalURL = "IsExternalUrl"
        case isForced = "IsForced"
        case isHearingImpaired = "IsHearingImpaired"
        case isInterlaced = "IsInterlaced"
        case isSupportsExternalStream = "SupportsExternalStream"
        case isTextSubtitleStream = "IsTextSubtitleStream"
        case language = "Language"
        case level = "Level"
        case packetLength = "PacketLength"
        case path = "Path"
        case pixelFormat = "PixelFormat"
        case profile = "Profile"
        case realFrameRate = "RealFrameRate"
        case refFrames = "RefFrames"
        case referenceFrameRate = "ReferenceFrameRate"
        case rotation = "Rotation"
        case sampleRate = "SampleRate"
        case score = "Score"
        case timeBase = "TimeBase"
        case title = "Title"
        case type = "Type"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case width = "Width"
    }
}

struct PlayerStateInfo: Codable, Hashable, Sendable {
    var canSeek: Bool? = nil
    var isMuted: Bool? = nil
    var isPaused: Bool? = nil
    var playMethod: PlayMethod? = nil
    var positionTicks: Int? = nil

    enum CodingKeys: String, CodingKey {
        case canSeek = "CanSeek"
        case isMuted = "IsMuted"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
        case positionTicks = "PositionTicks"
    }
}

struct SessionInfoDto: Codable, Hashable, Identifiable, Sendable {
    var applicationVersion: String? = nil
    var client: String? = nil
    var deviceID: String? = nil
    var deviceName: String? = nil
    var deviceType: String? = nil
    var id: String? = nil
    var isActive: Bool? = nil
    var isSupportsMediaControl: Bool? = nil
    var isSupportsRemoteControl: Bool? = nil
    var lastActivityDate: Date? = nil
    var lastPausedDate: Date? = nil
    var lastPlaybackCheckIn: Date? = nil
    var nowPlayingItem: BaseItemDto? = nil
    var nowPlayingQueueFullItems: [BaseItemDto]? = nil
    var nowViewingItem: BaseItemDto? = nil
    var playState: PlayerStateInfo? = nil
    var playableMediaTypes: [MediaType]? = nil
    var playlistItemID: String? = nil
    var remoteEndPoint: String? = nil
    var serverID: String? = nil
    var transcodingInfo: TranscodingInfo? = nil
    var userID: String? = nil
    var userName: String? = nil
    var userPrimaryImageTag: String? = nil

    enum CodingKeys: String, CodingKey {
        case applicationVersion = "ApplicationVersion"
        case client = "Client"
        case deviceID = "DeviceId"
        case deviceName = "DeviceName"
        case deviceType = "DeviceType"
        case id = "Id"
        case isActive = "IsActive"
        case isSupportsMediaControl = "SupportsMediaControl"
        case isSupportsRemoteControl = "SupportsRemoteControl"
        case lastActivityDate = "LastActivityDate"
        case lastPausedDate = "LastPausedDate"
        case lastPlaybackCheckIn = "LastPlaybackCheckIn"
        case nowPlayingItem = "NowPlayingItem"
        case nowPlayingQueueFullItems = "NowPlayingQueueFullItems"
        case nowViewingItem = "NowViewingItem"
        case playState = "PlayState"
        case playableMediaTypes = "PlayableMediaTypes"
        case playlistItemID = "PlaylistItemId"
        case remoteEndPoint = "RemoteEndPoint"
        case serverID = "ServerId"
        case transcodingInfo = "TranscodingInfo"
        case userID = "UserId"
        case userName = "UserName"
        case userPrimaryImageTag = "UserPrimaryImageTag"
    }
}

struct TranscodingInfo: Codable, Hashable, Sendable {
    var audioChannels: Int? = nil
    var audioCodec: String? = nil
    var bitrate: Int? = nil
    var completionPercentage: Double? = nil
    var container: String? = nil
    var framerate: Float? = nil
    var hardwareAccelerationType: HardwareAccelerationType? = nil
    var height: Int? = nil
    var isAudioDirect: Bool? = nil
    var isVideoDirect: Bool? = nil
    var transcodeReasons: [TranscodeReason]? = nil
    var videoCodec: String? = nil
    var width: Int? = nil

    enum CodingKeys: String, CodingKey {
        case audioChannels = "AudioChannels"
        case audioCodec = "AudioCodec"
        case bitrate = "Bitrate"
        case completionPercentage = "CompletionPercentage"
        case container = "Container"
        case framerate = "Framerate"
        case hardwareAccelerationType = "HardwareAccelerationType"
        case height = "Height"
        case isAudioDirect = "IsAudioDirect"
        case isVideoDirect = "IsVideoDirect"
        case transcodeReasons = "TranscodeReasons"
        case videoCodec = "VideoCodec"
        case width = "Width"
    }
}

struct TrickplayInfoDto: Codable, Hashable, Sendable {
    var width: Int? = nil
    var height: Int? = nil
    var tileWidth: Int? = nil
    var tileHeight: Int? = nil
    var thumbnailCount: Int? = nil
    var interval: Int? = nil
}

struct RemoteImageInfo: Codable, Hashable, Sendable {
    var communityRating: Double? = nil
    var height: Int? = nil
    var language: String? = nil
    var providerName: String? = nil
    var ratingType: RatingType? = nil
    var thumbnailURL: String? = nil
    var type: ImageType? = nil
    var url: String? = nil
    var voteCount: Int? = nil
    var width: Int? = nil

    enum CodingKeys: String, CodingKey {
        case communityRating = "CommunityRating"
        case height = "Height"
        case language = "Language"
        case providerName = "ProviderName"
        case ratingType = "RatingType"
        case thumbnailURL = "ThumbnailUrl"
        case type = "Type"
        case url = "Url"
        case voteCount = "VoteCount"
        case width = "Width"
    }
}

struct ImageInfo: Codable, Hashable, Sendable {
    var height: Int? = nil
    var imageIndex: Int? = nil
    var imageTag: String? = nil
    var imageType: ImageType? = nil
    var size: Int? = nil
    var width: Int? = nil

    enum CodingKeys: String, CodingKey {
        case height = "Height"
        case imageIndex = "ImageIndex"
        case imageTag = "ImageTag"
        case imageType = "ImageType"
        case size = "Size"
        case width = "Width"
    }
}

struct RemoteSearchResult: Codable, Sendable {
    var albumArtist: NameGuidPair? = nil
    var artists: [NameGuidPair]? = nil
    var imageURL: URL? = nil
    var indexNumber: Int? = nil
    var indexNumberEnd: Int? = nil
    var name: String? = nil
    var overview: String? = nil
    var parentIndexNumber: Int? = nil
    var premiereDate: Date? = nil
    var productionYear: Int? = nil
    var providerIDs: [String: String]? = nil
    var searchProviderName: String? = nil

    enum CodingKeys: String, CodingKey {
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case imageURL = "ImageUrl"
        case indexNumber = "IndexNumber"
        case indexNumberEnd = "IndexNumberEnd"
        case name = "Name"
        case overview = "Overview"
        case parentIndexNumber = "ParentIndexNumber"
        case premiereDate = "PremiereDate"
        case productionYear = "ProductionYear"
        case providerIDs = "ProviderIds"
        case searchProviderName = "SearchProviderName"
    }
}

struct DeviceProfile: Codable, Hashable, Sendable {
    var codecProfiles: [CodecProfile]? = nil
    var directPlayProfiles: [DirectPlayProfile]? = nil
    var maxStaticBitrate: Int? = nil
    var maxStreamingBitrate: Int? = nil
    var musicStreamingTranscodingBitrate: Int? = nil
    var subtitleProfiles: [SubtitleProfile]? = nil
    var transcodingProfiles: [TranscodingProfile]? = nil
}

struct DirectPlayProfile: Codable, Hashable, Sendable {
    var audioCodec: String? = nil
    var container: String? = nil
    var type: DlnaProfileType? = nil
    var videoCodec: String? = nil
}

struct TranscodingProfile: Codable, Hashable, Sendable {
    var `protocol`: MediaStreamProtocol? = nil
    var audioCodec: String? = nil
    var conditions: [ProfileCondition]? = nil
    var container: String? = nil
    var context: EncodingContext? = nil
    var enableAudioVbrEncoding: Bool? = nil
    var enableMpegtsM2TsMode: Bool? = nil
    var enableSubtitlesInManifest: Bool? = nil
    var isBreakOnNonKeyFrames: Bool? = nil
    var isCopyTimestamps: Bool? = nil
    var isEstimateContentLength: Bool? = nil
    var maxAudioChannels: String? = nil
    var minSegments: Int? = nil
    var segmentLength: Int? = nil
    var transcodeSeekInfo: TranscodeSeekInfo? = nil
    var type: DlnaProfileType? = nil
    var videoCodec: String? = nil
}

struct SubtitleProfile: Codable, Hashable, Sendable {
    var container: String? = nil
    var didlMode: String? = nil
    var format: String? = nil
    var language: String? = nil
    var method: SubtitleDeliveryMethod? = nil
}

struct CodecProfile: Codable, Hashable, Sendable {
    var applyConditions: [ProfileCondition]? = nil
    var codec: String? = nil
    var conditions: [ProfileCondition]? = nil
    var container: String? = nil
    var type: CodecType? = nil
}

struct ProfileCondition: Codable, Hashable, Sendable {
    var condition: ProfileConditionType? = nil
    var isRequired: Bool? = nil
    var property: ProfileConditionValue? = nil
    var value: String? = nil
}

enum BaseItemKind: String, Codable, CaseIterable, Sendable {
    case aggregateFolder = "AggregateFolder"
    case audio = "Audio"
    case audioBook = "AudioBook"
    case basePluginFolder = "BasePluginFolder"
    case book = "Book"
    case boxSet = "BoxSet"
    case channel = "Channel"
    case channelFolderItem = "ChannelFolderItem"
    case collectionFolder = "CollectionFolder"
    case episode = "Episode"
    case folder = "Folder"
    case genre = "Genre"
    case manualPlaylistsFolder = "ManualPlaylistsFolder"
    case movie = "Movie"
    case liveTvChannel = "LiveTvChannel"
    case liveTvProgram = "LiveTvProgram"
    case musicAlbum = "MusicAlbum"
    case musicArtist = "MusicArtist"
    case musicGenre = "MusicGenre"
    case musicVideo = "MusicVideo"
    case person = "Person"
    case photo = "Photo"
    case photoAlbum = "PhotoAlbum"
    case playlist = "Playlist"
    case playlistsFolder = "PlaylistsFolder"
    case program = "Program"
    case recording = "Recording"
    case season = "Season"
    case series = "Series"
    case studio = "Studio"
    case trailer = "Trailer"
    case tvChannel = "TvChannel"
    case tvProgram = "TvProgram"
    case userRootFolder = "UserRootFolder"
    case userView = "UserView"
    case video = "Video"
    case year = "Year"
}

enum CollectionType: String, Codable, CaseIterable, Sendable {
    case unknown
    case movies
    case tvshows
    case music
    case musicvideos
    case trailers
    case homevideos
    case boxsets
    case books
    case photos
    case livetv
    case playlists
    case folders
}

enum ImageType: String, Codable, CaseIterable, Sendable {
    case primary = "Primary"
    case art = "Art"
    case backdrop = "Backdrop"
    case banner = "Banner"
    case logo = "Logo"
    case thumb = "Thumb"
    case disc = "Disc"
    case box = "Box"
    case screenshot = "Screenshot"
    case menu = "Menu"
    case chapter = "Chapter"
    case boxRear = "BoxRear"
    case profile = "Profile"
}

enum ExtraType: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case clip = "Clip"
    case trailer = "Trailer"
    case behindTheScenes = "BehindTheScenes"
    case deletedScene = "DeletedScene"
    case interview = "Interview"
    case scene = "Scene"
    case sample = "Sample"
    case themeSong = "ThemeSong"
    case themeVideo = "ThemeVideo"
    case featurette = "Featurette"
    case short = "Short"
}

enum PersonKind: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case actor = "Actor"
    case director = "Director"
    case composer = "Composer"
    case writer = "Writer"
    case guestStar = "GuestStar"
    case producer = "Producer"
    case conductor = "Conductor"
    case lyricist = "Lyricist"
    case arranger = "Arranger"
    case engineer = "Engineer"
    case mixer = "Mixer"
    case remixer = "Remixer"
    case creator = "Creator"
    case artist = "Artist"
    case albumArtist = "AlbumArtist"
    case author = "Author"
    case illustrator = "Illustrator"
    case penciller = "Penciller"
    case inker = "Inker"
    case colorist = "Colorist"
    case letterer = "Letterer"
    case coverArtist = "CoverArtist"
    case editor = "Editor"
    case translator = "Translator"
}

enum MediaStreamType: String, Codable, CaseIterable, Sendable {
    case audio = "Audio"
    case video = "Video"
    case subtitle = "Subtitle"
    case embeddedImage = "EmbeddedImage"
    case data = "Data"
    case lyric = "Lyric"
    case attachment = "Attachment"
}

enum SubtitleDeliveryMethod: String, Codable, CaseIterable, Sendable {
    case encode = "Encode"
    case embed = "Embed"
    case external = "External"
    case hls = "Hls"
    case drop = "Drop"
}

enum PlayMethod: String, Codable, CaseIterable, Sendable {
    case transcode = "Transcode"
    case directStream = "DirectStream"
    case directPlay = "DirectPlay"
}

enum TranscodeReason: String, Codable, CaseIterable, Sendable {
    case containerNotSupported = "ContainerNotSupported"
    case videoCodecNotSupported = "VideoCodecNotSupported"
    case audioCodecNotSupported = "AudioCodecNotSupported"
    case subtitleCodecNotSupported = "SubtitleCodecNotSupported"
    case audioIsExternal = "AudioIsExternal"
    case secondaryAudioNotSupported = "SecondaryAudioNotSupported"
    case videoProfileNotSupported = "VideoProfileNotSupported"
    case videoLevelNotSupported = "VideoLevelNotSupported"
    case videoResolutionNotSupported = "VideoResolutionNotSupported"
    case videoBitDepthNotSupported = "VideoBitDepthNotSupported"
    case videoFramerateNotSupported = "VideoFramerateNotSupported"
    case refFramesNotSupported = "RefFramesNotSupported"
    case anamorphicVideoNotSupported = "AnamorphicVideoNotSupported"
    case interlacedVideoNotSupported = "InterlacedVideoNotSupported"
    case audioChannelsNotSupported = "AudioChannelsNotSupported"
    case audioProfileNotSupported = "AudioProfileNotSupported"
    case audioSampleRateNotSupported = "AudioSampleRateNotSupported"
    case audioBitDepthNotSupported = "AudioBitDepthNotSupported"
    case containerBitrateExceedsLimit = "ContainerBitrateExceedsLimit"
    case videoBitrateNotSupported = "VideoBitrateNotSupported"
    case audioBitrateNotSupported = "AudioBitrateNotSupported"
    case unknownVideoStreamInfo = "UnknownVideoStreamInfo"
    case unknownAudioStreamInfo = "UnknownAudioStreamInfo"
    case directPlayError = "DirectPlayError"
    case videoRangeTypeNotSupported = "VideoRangeTypeNotSupported"
    case videoCodecTagNotSupported = "VideoCodecTagNotSupported"
    case streamCountExceedsLimit = "StreamCountExceedsLimit"
}

enum Video3DFormat: String, Codable, CaseIterable, Sendable {
    case halfSideBySide = "HalfSideBySide"
    case fullSideBySide = "FullSideBySide"
    case fullTopAndBottom = "FullTopAndBottom"
    case halfTopAndBottom = "HalfTopAndBottom"
    case mvc = "MVC"
}

enum VideoRangeType: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case dovi = "DOVI"
    case doviWithHDR10 = "DOVIWithHDR10"
    case doviWithHLG = "DOVIWithHLG"
    case doviWithSDR = "DOVIWithSDR"
    case doviWithEL = "DOVIWithEL"
    case doviWithHDR10Plus = "DOVIWithHDR10Plus"
    case doviWithELHDR10Plus = "DOVIWithELHDR10Plus"
    case doviInvalid = "DOVIInvalid"
    case hdr10Plus = "HDR10Plus"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.unknown.rawValue
        self = Self(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum VideoRange: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case sdr = "SDR"
    case hdr = "HDR"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.unknown.rawValue
        self = Self(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum MediaType: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case video = "Video"
    case audio = "Audio"
    case photo = "Photo"
    case book = "Book"
}

enum ChannelType: String, Codable, CaseIterable, Sendable {
    case tv = "TV"
    case radio = "Radio"
}

enum LocationType: String, Codable, CaseIterable, Sendable {
    case fileSystem = "FileSystem"
    case remote = "Remote"
    case virtual = "Virtual"
    case offline = "Offline"
}

enum MetadataField: Codable, CaseIterable, Hashable, Sendable {
    case cast
    case genres
    case productionLocations
    case studios
    case tags
    case name
    case originalTitle
    case sortName
    case overview
    case runtime
    case officialRating
    case index
    case unknown(String)

    static let allCases: [MetadataField] = [
        .cast,
        .genres,
        .productionLocations,
        .studios,
        .tags,
        .name,
        .originalTitle,
        .sortName,
        .overview,
        .runtime,
        .officialRating,
        .index,
    ]

    var rawValue: String {
        switch self {
        case .cast:
            "Cast"
        case .genres:
            "Genres"
        case .productionLocations:
            "ProductionLocations"
        case .studios:
            "Studios"
        case .tags:
            "Tags"
        case .name:
            "Name"
        case .originalTitle:
            "OriginalTitle"
        case .sortName:
            "SortName"
        case .overview:
            "Overview"
        case .runtime:
            "Runtime"
        case .officialRating:
            "OfficialRating"
        case .index:
            "Index"
        case let .unknown(value):
            value
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "Cast":
            self = .cast
        case "Genres":
            self = .genres
        case "ProductionLocations":
            self = .productionLocations
        case "Studios":
            self = .studios
        case "Tags":
            self = .tags
        case "Name":
            self = .name
        case "OriginalTitle":
            self = .originalTitle
        case "SortName":
            self = .sortName
        case "Overview":
            self = .overview
        case "Runtime":
            self = .runtime
        case "OfficialRating":
            self = .officialRating
        case "Index":
            self = .index
        default:
            self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum MediaProtocol: String, Codable, CaseIterable, Sendable {
    case file = "File"
    case http = "Http"
    case rtmp = "Rtmp"
    case rtsp = "Rtsp"
    case udp = "Udp"
    case rtp = "Rtp"
    case ftp = "Ftp"
}

enum MediaStreamProtocol: String, Codable, CaseIterable, Sendable {
    case http
    case hls
}

enum MediaSourceType: String, Codable, CaseIterable, Sendable {
    case `default` = "Default"
    case grouping = "Grouping"
    case placeholder = "Placeholder"
}

enum VideoType: String, Codable, CaseIterable, Sendable {
    case videoFile = "VideoFile"
    case iso = "Iso"
    case dvd = "Dvd"
    case bluRay = "BluRay"
}

enum PlayAccess: String, Codable, CaseIterable, Sendable {
    case full = "Full"
    case none = "None"
}

enum SortOrder: String, Codable, CaseIterable, Sendable {
    case ascending = "Ascending"
    case descending = "Descending"
}

enum ItemFields: String, Codable, CaseIterable, Sendable {
    case airTime = "AirTime"
    case canDelete = "CanDelete"
    case canDownload = "CanDownload"
    case channelInfo = "ChannelInfo"
    case chapters = "Chapters"
    case trickplay = "Trickplay"
    case childCount = "ChildCount"
    case cumulativeRunTimeTicks = "CumulativeRunTimeTicks"
    case customRating = "CustomRating"
    case dateCreated = "DateCreated"
    case dateLastMediaAdded = "DateLastMediaAdded"
    case displayPreferencesID = "DisplayPreferencesId"
    case etag = "Etag"
    case externalURLs = "ExternalUrls"
    case genres = "Genres"
    case itemCounts = "ItemCounts"
    case mediaSourceCount = "MediaSourceCount"
    case mediaSources = "MediaSources"
    case originalTitle = "OriginalTitle"
    case overview = "Overview"
    case parentID = "ParentId"
    case path = "Path"
    case people = "People"
    case playAccess = "PlayAccess"
    case productionLocations = "ProductionLocations"
    case providerIDs = "ProviderIds"
    case primaryImageAspectRatio = "PrimaryImageAspectRatio"
    case recursiveItemCount = "RecursiveItemCount"
    case settings = "Settings"
    case seriesStudio = "SeriesStudio"
    case sortName = "SortName"
    case specialEpisodeNumbers = "SpecialEpisodeNumbers"
    case studios = "Studios"
    case taglines = "Taglines"
    case tags = "Tags"
    case remoteTrailers = "RemoteTrailers"
    case mediaStreams = "MediaStreams"
    case seasonUserData = "SeasonUserData"
    case dateLastRefreshed = "DateLastRefreshed"
    case dateLastSaved = "DateLastSaved"
    case refreshState = "RefreshState"
    case channelImage = "ChannelImage"
    case enableMediaSourceDisplay = "EnableMediaSourceDisplay"
    case width = "Width"
    case height = "Height"
    case extraIDs = "ExtraIds"
    case localTrailerCount = "LocalTrailerCount"
    case isHD = "IsHD"
    case specialFeatureCount = "SpecialFeatureCount"
}

enum EmbyItemTrait: String, Codable, CaseIterable, Sendable {
    case isFolder = "IsFolder"
    case isNotFolder = "IsNotFolder"
    case isUnplayed = "IsUnplayed"
    case isPlayed = "IsPlayed"
    case isFavorite = "IsFavorite"
    case isResumable = "IsResumable"
    case likes = "Likes"
    case dislikes = "Dislikes"
    case isFavoriteOrLikes = "IsFavoriteOrLikes"
}

enum ItemSortBy: String, Codable, CaseIterable, Sendable {
    case airedEpisodeOrder = "AiredEpisodeOrder"
    case airTime = "AirTime"
    case album = "Album"
    case albumArtist = "AlbumArtist"
    case artist = "Artist"
    case communityRating = "CommunityRating"
    case criticRating = "CriticRating"
    case dateCreated = "DateCreated"
    case dateLastContentAdded = "DateLastContentAdded"
    case datePlayed = "DatePlayed"
    case `default` = "Default"
    case indexNumber = "IndexNumber"
    case isFavoriteOrLiked = "IsFavoriteOrLiked"
    case isFolder = "IsFolder"
    case isPlayed = "IsPlayed"
    case isUnplayed = "IsUnplayed"
    case name = "Name"
    case officialRating = "OfficialRating"
    case parentIndexNumber = "ParentIndexNumber"
    case playCount = "PlayCount"
    case premiereDate = "PremiereDate"
    case productionYear = "ProductionYear"
    case random = "Random"
    case runtime = "Runtime"
    case seriesDatePlayed = "SeriesDatePlayed"
    case seriesSortName = "SeriesSortName"
    case sortName = "SortName"
    case startDate = "StartDate"
    case studio = "Studio"
    case videoBitRate = "VideoBitRate"
}

enum ProgramAudio: String, Codable, CaseIterable, Sendable {
    case mono = "Mono"
    case stereo = "Stereo"
    case dolby = "Dolby"
    case dolbyDigital = "DolbyDigital"
    case thx = "Thx"
    case atmos = "Atmos"
}

enum IsoType: String, Codable, CaseIterable, Sendable {
    case dvd = "Dvd"
    case bluRay = "BluRay"
}

enum ImageOrientation: String, Codable, CaseIterable, Sendable {
    case topLeft = "TopLeft"
    case topRight = "TopRight"
    case bottomRight = "BottomRight"
    case bottomLeft = "BottomLeft"
    case leftTop = "LeftTop"
    case rightTop = "RightTop"
    case rightBottom = "RightBottom"
    case leftBottom = "LeftBottom"
}

enum AudioSpatialFormat: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case dolbyAtmos = "DolbyAtmos"
    case dtsx = "DTSX"
}

enum TransportStreamTimestamp: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case zero = "Zero"
    case valid = "Valid"
}

enum HardwareAccelerationType: String, Codable, CaseIterable, Sendable {
    case none
    case amf
    case qsv
    case nvenc
    case v4l2m2m
    case vaapi
    case videotoolbox
    case rkmpp
}

enum RatingType: String, Codable, CaseIterable, Sendable {
    case score = "Score"
    case likes = "Likes"
}

enum DlnaProfileType: String, Codable, CaseIterable, Sendable {
    case audio = "Audio"
    case video = "Video"
    case photo = "Photo"
    case subtitle = "Subtitle"
    case lyric = "Lyric"
}

enum EncodingContext: String, Codable, CaseIterable, Sendable {
    case streaming = "Streaming"
    case `static` = "Static"
}

enum TranscodeSeekInfo: String, Codable, CaseIterable, Sendable {
    case auto = "Auto"
    case bytes = "Bytes"
}

enum ProfileConditionType: String, Codable, CaseIterable, Sendable {
    case equals = "Equals"
    case notEquals = "NotEquals"
    case lessThanEqual = "LessThanEqual"
    case greaterThanEqual = "GreaterThanEqual"
    case equalsAny = "EqualsAny"
}

enum ProfileConditionValue: String, Codable, CaseIterable, Sendable {
    case audioChannels = "AudioChannels"
    case audioBitrate = "AudioBitrate"
    case audioProfile = "AudioProfile"
    case width = "Width"
    case height = "Height"
    case has64BitOffsets = "Has64BitOffsets"
    case packetLength = "PacketLength"
    case videoBitDepth = "VideoBitDepth"
    case videoBitrate = "VideoBitrate"
    case videoFramerate = "VideoFramerate"
    case videoLevel = "VideoLevel"
    case videoProfile = "VideoProfile"
    case videoTimestamp = "VideoTimestamp"
    case isAnamorphic = "IsAnamorphic"
    case refFrames = "RefFrames"
    case numAudioStreams = "NumAudioStreams"
    case numVideoStreams = "NumVideoStreams"
    case isSecondaryAudio = "IsSecondaryAudio"
    case videoCodecTag = "VideoCodecTag"
    case isAvc = "IsAvc"
    case isInterlaced = "IsInterlaced"
    case audioSampleRate = "AudioSampleRate"
    case audioBitDepth = "AudioBitDepth"
    case videoRangeType = "VideoRangeType"
    case numStreams = "NumStreams"
}

enum CodecType: String, Codable, CaseIterable, Sendable {
    case video = "Video"
    case videoAudio = "VideoAudio"
    case audio = "Audio"
}
