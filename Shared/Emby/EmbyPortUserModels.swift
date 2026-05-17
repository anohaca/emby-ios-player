//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct UserDto: Codable, Hashable, Identifiable, Sendable {
    var configuration: UserConfiguration?
    var enableAutoLogin: Bool?
    var hasConfiguredEasyPassword: Bool?
    var hasConfiguredPassword: Bool?
    var hasPassword: Bool?
    var id: String?
    var lastActivityDate: Date?
    var lastLoginDate: Date?
    var name: String?
    var policy: UserPolicy?
    var primaryImageAspectRatio: Double?
    var primaryImageTag: String?
    var serverID: String?
    var serverName: String?

    enum CodingKeys: String, CodingKey {
        case configuration = "Configuration"
        case enableAutoLogin = "EnableAutoLogin"
        case hasConfiguredEasyPassword = "HasConfiguredEasyPassword"
        case hasConfiguredPassword = "HasConfiguredPassword"
        case hasPassword = "HasPassword"
        case id = "Id"
        case lastActivityDate = "LastActivityDate"
        case lastLoginDate = "LastLoginDate"
        case name = "Name"
        case policy = "Policy"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case primaryImageTag = "PrimaryImageTag"
        case serverID = "ServerId"
        case serverName = "ServerName"
    }

    init(
        configuration: UserConfiguration? = nil,
        enableAutoLogin: Bool? = nil,
        hasConfiguredEasyPassword: Bool? = nil,
        hasConfiguredPassword: Bool? = nil,
        hasPassword: Bool? = nil,
        id: String? = nil,
        lastActivityDate: Date? = nil,
        lastLoginDate: Date? = nil,
        name: String? = nil,
        policy: UserPolicy? = nil,
        primaryImageAspectRatio: Double? = nil,
        primaryImageTag: String? = nil,
        serverID: String? = nil,
        serverName: String? = nil
    ) {
        self.configuration = configuration
        self.enableAutoLogin = enableAutoLogin
        self.hasConfiguredEasyPassword = hasConfiguredEasyPassword
        self.hasConfiguredPassword = hasConfiguredPassword
        self.hasPassword = hasPassword
        self.id = id
        self.lastActivityDate = lastActivityDate
        self.lastLoginDate = lastLoginDate
        self.name = name
        self.policy = policy
        self.primaryImageAspectRatio = primaryImageAspectRatio
        self.primaryImageTag = primaryImageTag
        self.serverID = serverID
        self.serverName = serverName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.configuration = try container.decodeIfPresent(UserConfiguration.self, forKey: .configuration)
        self.enableAutoLogin = try container.decodeIfPresent(Bool.self, forKey: .enableAutoLogin)
        self.hasConfiguredEasyPassword = try container.decodeIfPresent(Bool.self, forKey: .hasConfiguredEasyPassword)
        self.hasConfiguredPassword = try container.decodeIfPresent(Bool.self, forKey: .hasConfiguredPassword)
        self.hasPassword = try container.decodeIfPresent(Bool.self, forKey: .hasPassword)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.lastActivityDate = try container.decodeEmbyDateIfPresent(forKey: .lastActivityDate)
        self.lastLoginDate = try container.decodeEmbyDateIfPresent(forKey: .lastLoginDate)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.policy = try container.decodeIfPresent(UserPolicy.self, forKey: .policy)
        self.primaryImageAspectRatio = try container.decodeIfPresent(Double.self, forKey: .primaryImageAspectRatio)
        self.primaryImageTag = try container.decodeIfPresent(String.self, forKey: .primaryImageTag)
        self.serverID = try container.decodeIfPresent(String.self, forKey: .serverID)
        self.serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(configuration, forKey: .configuration)
        try container.encodeIfPresent(enableAutoLogin, forKey: .enableAutoLogin)
        try container.encodeIfPresent(hasConfiguredEasyPassword, forKey: .hasConfiguredEasyPassword)
        try container.encodeIfPresent(hasConfiguredPassword, forKey: .hasConfiguredPassword)
        try container.encodeIfPresent(hasPassword, forKey: .hasPassword)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeEmbyDateIfPresent(lastActivityDate, forKey: .lastActivityDate)
        try container.encodeEmbyDateIfPresent(lastLoginDate, forKey: .lastLoginDate)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(policy, forKey: .policy)
        try container.encodeIfPresent(primaryImageAspectRatio, forKey: .primaryImageAspectRatio)
        try container.encodeIfPresent(primaryImageTag, forKey: .primaryImageTag)
        try container.encodeIfPresent(serverID, forKey: .serverID)
        try container.encodeIfPresent(serverName, forKey: .serverName)
    }
}

struct UserConfiguration: Codable, Hashable, Sendable {
    var audioLanguagePreference: String?
    var castReceiverID: String?
    var enableLocalPassword: Bool?
    var enableNextEpisodeAutoPlay: Bool?
    var groupedFolders: [String]?
    var isDisplayCollectionsView: Bool?
    var isDisplayMissingEpisodes: Bool?
    var isHidePlayedInLatest: Bool?
    var isPlayDefaultAudioTrack: Bool?
    var isRememberAudioSelections: Bool?
    var isRememberSubtitleSelections: Bool?
    var latestItemsExcludes: [String]?
    var myMediaExcludes: [String]?
    var orderedViews: [String]?
    var subtitleLanguagePreference: String?
    var subtitleMode: SubtitlePlaybackMode?

    enum CodingKeys: String, CodingKey {
        case audioLanguagePreference = "AudioLanguagePreference"
        case castReceiverID = "CastReceiverId"
        case enableLocalPassword = "EnableLocalPassword"
        case enableNextEpisodeAutoPlay = "EnableNextEpisodeAutoPlay"
        case groupedFolders = "GroupedFolders"
        case isDisplayCollectionsView = "DisplayCollectionsView"
        case isDisplayMissingEpisodes = "DisplayMissingEpisodes"
        case isHidePlayedInLatest = "HidePlayedInLatest"
        case isPlayDefaultAudioTrack = "PlayDefaultAudioTrack"
        case isRememberAudioSelections = "RememberAudioSelections"
        case isRememberSubtitleSelections = "RememberSubtitleSelections"
        case latestItemsExcludes = "LatestItemsExcludes"
        case myMediaExcludes = "MyMediaExcludes"
        case orderedViews = "OrderedViews"
        case subtitleLanguagePreference = "SubtitleLanguagePreference"
        case subtitleMode = "SubtitleMode"
    }
}

struct UserPolicy: Codable, Hashable, Sendable {
    var accessSchedules: [AccessSchedule]?
    var allowedTags: [String]?
    var authenticationProviderID: String
    var blockUnratedItems: [UnratedItem]?
    var blockedChannels: [String]?
    var blockedMediaFolders: [String]?
    var blockedTags: [String]?
    var enableAllChannels: Bool?
    var enableAllDevices: Bool?
    var enableAllFolders: Bool?
    var enableAudioPlaybackTranscoding: Bool?
    var enableCollectionManagement: Bool
    var enableContentDeletion: Bool?
    var enableContentDeletionFromFolders: [String]?
    var enableContentDownloading: Bool?
    var enableLiveTvAccess: Bool?
    var enableLiveTvManagement: Bool?
    var enableLyricManagement: Bool
    var enableMediaConversion: Bool?
    var enableMediaPlayback: Bool?
    var enablePlaybackRemuxing: Bool?
    var enablePublicSharing: Bool?
    var enableRemoteAccess: Bool?
    var enableRemoteControlOfOtherUsers: Bool?
    var enableSharedDeviceControl: Bool?
    var enableSubtitleManagement: Bool
    var enableSyncTranscoding: Bool?
    var enableUserPreferenceAccess: Bool?
    var enableVideoPlaybackTranscoding: Bool?
    var enabledChannels: [String]?
    var enabledDevices: [String]?
    var enabledFolders: [String]?
    var invalidLoginAttemptCount: Int?
    var isAdministrator: Bool?
    var isDisabled: Bool?
    var isForceRemoteSourceTranscoding: Bool?
    var isHidden: Bool?
    var loginAttemptsBeforeLockout: Int?
    var maxActiveSessions: Int?
    var maxParentalRating: Int?
    var maxParentalSubRating: Int?
    var passwordResetProviderID: String
    var remoteClientBitrateLimit: Int?
    var syncPlayAccess: SyncPlayUserAccessType?

    enum CodingKeys: String, CodingKey {
        case accessSchedules = "AccessSchedules"
        case allowedTags = "AllowedTags"
        case authenticationProviderID = "AuthenticationProviderId"
        case blockUnratedItems = "BlockUnratedItems"
        case blockedChannels = "BlockedChannels"
        case blockedMediaFolders = "BlockedMediaFolders"
        case blockedTags = "BlockedTags"
        case enableAllChannels = "EnableAllChannels"
        case enableAllDevices = "EnableAllDevices"
        case enableAllFolders = "EnableAllFolders"
        case enableAudioPlaybackTranscoding = "EnableAudioPlaybackTranscoding"
        case enableCollectionManagement = "EnableCollectionManagement"
        case enableContentDeletion = "EnableContentDeletion"
        case enableContentDeletionFromFolders = "EnableContentDeletionFromFolders"
        case enableContentDownloading = "EnableContentDownloading"
        case enableLiveTvAccess = "EnableLiveTvAccess"
        case enableLiveTvManagement = "EnableLiveTvManagement"
        case enableLyricManagement = "EnableLyricManagement"
        case enableMediaConversion = "EnableMediaConversion"
        case enableMediaPlayback = "EnableMediaPlayback"
        case enablePlaybackRemuxing = "EnablePlaybackRemuxing"
        case enablePublicSharing = "EnablePublicSharing"
        case enableRemoteAccess = "EnableRemoteAccess"
        case enableRemoteControlOfOtherUsers = "EnableRemoteControlOfOtherUsers"
        case enableSharedDeviceControl = "EnableSharedDeviceControl"
        case enableSubtitleManagement = "EnableSubtitleManagement"
        case enableSyncTranscoding = "EnableSyncTranscoding"
        case enableUserPreferenceAccess = "EnableUserPreferenceAccess"
        case enableVideoPlaybackTranscoding = "EnableVideoPlaybackTranscoding"
        case enabledChannels = "EnabledChannels"
        case enabledDevices = "EnabledDevices"
        case enabledFolders = "EnabledFolders"
        case invalidLoginAttemptCount = "InvalidLoginAttemptCount"
        case isAdministrator = "IsAdministrator"
        case isDisabled = "IsDisabled"
        case isForceRemoteSourceTranscoding = "ForceRemoteSourceTranscoding"
        case isHidden = "IsHidden"
        case loginAttemptsBeforeLockout = "LoginAttemptsBeforeLockout"
        case maxActiveSessions = "MaxActiveSessions"
        case maxParentalRating = "MaxParentalRating"
        case maxParentalSubRating = "MaxParentalSubRating"
        case passwordResetProviderID = "PasswordResetProviderId"
        case remoteClientBitrateLimit = "RemoteClientBitrateLimit"
        case syncPlayAccess = "SyncPlayAccess"
    }

    init(
        accessSchedules: [AccessSchedule]? = nil,
        allowedTags: [String]? = nil,
        authenticationProviderID: String,
        blockUnratedItems: [UnratedItem]? = nil,
        blockedChannels: [String]? = nil,
        blockedMediaFolders: [String]? = nil,
        blockedTags: [String]? = nil,
        enableAllChannels: Bool? = nil,
        enableAllDevices: Bool? = nil,
        enableAllFolders: Bool? = nil,
        enableAudioPlaybackTranscoding: Bool? = nil,
        enableCollectionManagement: Bool = false,
        enableContentDeletion: Bool? = nil,
        enableContentDeletionFromFolders: [String]? = nil,
        enableContentDownloading: Bool? = nil,
        enableLiveTvAccess: Bool? = nil,
        enableLiveTvManagement: Bool? = nil,
        enableLyricManagement: Bool = false,
        enableMediaConversion: Bool? = nil,
        enableMediaPlayback: Bool? = nil,
        enablePlaybackRemuxing: Bool? = nil,
        enablePublicSharing: Bool? = nil,
        enableRemoteAccess: Bool? = nil,
        enableRemoteControlOfOtherUsers: Bool? = nil,
        enableSharedDeviceControl: Bool? = nil,
        enableSubtitleManagement: Bool = false,
        enableSyncTranscoding: Bool? = nil,
        enableUserPreferenceAccess: Bool? = nil,
        enableVideoPlaybackTranscoding: Bool? = nil,
        enabledChannels: [String]? = nil,
        enabledDevices: [String]? = nil,
        enabledFolders: [String]? = nil,
        invalidLoginAttemptCount: Int? = nil,
        isAdministrator: Bool? = nil,
        isDisabled: Bool? = nil,
        isForceRemoteSourceTranscoding: Bool? = nil,
        isHidden: Bool? = nil,
        loginAttemptsBeforeLockout: Int? = nil,
        maxActiveSessions: Int? = nil,
        maxParentalRating: Int? = nil,
        maxParentalSubRating: Int? = nil,
        passwordResetProviderID: String,
        remoteClientBitrateLimit: Int? = nil,
        syncPlayAccess: SyncPlayUserAccessType? = nil
    ) {
        self.accessSchedules = accessSchedules
        self.allowedTags = allowedTags
        self.authenticationProviderID = authenticationProviderID
        self.blockUnratedItems = blockUnratedItems
        self.blockedChannels = blockedChannels
        self.blockedMediaFolders = blockedMediaFolders
        self.blockedTags = blockedTags
        self.enableAllChannels = enableAllChannels
        self.enableAllDevices = enableAllDevices
        self.enableAllFolders = enableAllFolders
        self.enableAudioPlaybackTranscoding = enableAudioPlaybackTranscoding
        self.enableCollectionManagement = enableCollectionManagement
        self.enableContentDeletion = enableContentDeletion
        self.enableContentDeletionFromFolders = enableContentDeletionFromFolders
        self.enableContentDownloading = enableContentDownloading
        self.enableLiveTvAccess = enableLiveTvAccess
        self.enableLiveTvManagement = enableLiveTvManagement
        self.enableLyricManagement = enableLyricManagement
        self.enableMediaConversion = enableMediaConversion
        self.enableMediaPlayback = enableMediaPlayback
        self.enablePlaybackRemuxing = enablePlaybackRemuxing
        self.enablePublicSharing = enablePublicSharing
        self.enableRemoteAccess = enableRemoteAccess
        self.enableRemoteControlOfOtherUsers = enableRemoteControlOfOtherUsers
        self.enableSharedDeviceControl = enableSharedDeviceControl
        self.enableSubtitleManagement = enableSubtitleManagement
        self.enableSyncTranscoding = enableSyncTranscoding
        self.enableUserPreferenceAccess = enableUserPreferenceAccess
        self.enableVideoPlaybackTranscoding = enableVideoPlaybackTranscoding
        self.enabledChannels = enabledChannels
        self.enabledDevices = enabledDevices
        self.enabledFolders = enabledFolders
        self.invalidLoginAttemptCount = invalidLoginAttemptCount
        self.isAdministrator = isAdministrator
        self.isDisabled = isDisabled
        self.isForceRemoteSourceTranscoding = isForceRemoteSourceTranscoding
        self.isHidden = isHidden
        self.loginAttemptsBeforeLockout = loginAttemptsBeforeLockout
        self.maxActiveSessions = maxActiveSessions
        self.maxParentalRating = maxParentalRating
        self.maxParentalSubRating = maxParentalSubRating
        self.passwordResetProviderID = passwordResetProviderID
        self.remoteClientBitrateLimit = remoteClientBitrateLimit
        self.syncPlayAccess = syncPlayAccess
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.accessSchedules = try container.decodeIfPresent([AccessSchedule].self, forKey: .accessSchedules)
        self.allowedTags = try container.decodeIfPresent([String].self, forKey: .allowedTags)
        self.authenticationProviderID = try container.decodeIfPresent(String.self, forKey: .authenticationProviderID) ?? ""
        self.blockUnratedItems = try container.decodeIfPresent([UnratedItem].self, forKey: .blockUnratedItems)
        self.blockedChannels = try container.decodeIfPresent([String].self, forKey: .blockedChannels)
        self.blockedMediaFolders = try container.decodeIfPresent([String].self, forKey: .blockedMediaFolders)
        self.blockedTags = try container.decodeIfPresent([String].self, forKey: .blockedTags)
        self.enableAllChannels = try container.decodeIfPresent(Bool.self, forKey: .enableAllChannels)
        self.enableAllDevices = try container.decodeIfPresent(Bool.self, forKey: .enableAllDevices)
        self.enableAllFolders = try container.decodeIfPresent(Bool.self, forKey: .enableAllFolders)
        self.enableAudioPlaybackTranscoding = try container.decodeIfPresent(Bool.self, forKey: .enableAudioPlaybackTranscoding)
        self.enableCollectionManagement = try container.decodeIfPresent(Bool.self, forKey: .enableCollectionManagement) ?? false
        self.enableContentDeletion = try container.decodeIfPresent(Bool.self, forKey: .enableContentDeletion)
        self.enableContentDeletionFromFolders = try container.decodeIfPresent([String].self, forKey: .enableContentDeletionFromFolders)
        self.enableContentDownloading = try container.decodeIfPresent(Bool.self, forKey: .enableContentDownloading)
        self.enableLiveTvAccess = try container.decodeIfPresent(Bool.self, forKey: .enableLiveTvAccess)
        self.enableLiveTvManagement = try container.decodeIfPresent(Bool.self, forKey: .enableLiveTvManagement)
        self.enableLyricManagement = try container.decodeIfPresent(Bool.self, forKey: .enableLyricManagement) ?? false
        self.enableMediaConversion = try container.decodeIfPresent(Bool.self, forKey: .enableMediaConversion)
        self.enableMediaPlayback = try container.decodeIfPresent(Bool.self, forKey: .enableMediaPlayback)
        self.enablePlaybackRemuxing = try container.decodeIfPresent(Bool.self, forKey: .enablePlaybackRemuxing)
        self.enablePublicSharing = try container.decodeIfPresent(Bool.self, forKey: .enablePublicSharing)
        self.enableRemoteAccess = try container.decodeIfPresent(Bool.self, forKey: .enableRemoteAccess)
        self.enableRemoteControlOfOtherUsers = try container.decodeIfPresent(Bool.self, forKey: .enableRemoteControlOfOtherUsers)
        self.enableSharedDeviceControl = try container.decodeIfPresent(Bool.self, forKey: .enableSharedDeviceControl)
        self.enableSubtitleManagement = try container.decodeIfPresent(Bool.self, forKey: .enableSubtitleManagement) ?? false
        self.enableSyncTranscoding = try container.decodeIfPresent(Bool.self, forKey: .enableSyncTranscoding)
        self.enableUserPreferenceAccess = try container.decodeIfPresent(Bool.self, forKey: .enableUserPreferenceAccess)
        self.enableVideoPlaybackTranscoding = try container.decodeIfPresent(Bool.self, forKey: .enableVideoPlaybackTranscoding)
        self.enabledChannels = try container.decodeIfPresent([String].self, forKey: .enabledChannels)
        self.enabledDevices = try container.decodeIfPresent([String].self, forKey: .enabledDevices)
        self.enabledFolders = try container.decodeIfPresent([String].self, forKey: .enabledFolders)
        self.invalidLoginAttemptCount = try container.decodeIfPresent(Int.self, forKey: .invalidLoginAttemptCount)
        self.isAdministrator = try container.decodeIfPresent(Bool.self, forKey: .isAdministrator)
        self.isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled)
        self.isForceRemoteSourceTranscoding = try container.decodeIfPresent(Bool.self, forKey: .isForceRemoteSourceTranscoding)
        self.isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden)
        self.loginAttemptsBeforeLockout = try container.decodeIfPresent(Int.self, forKey: .loginAttemptsBeforeLockout)
        self.maxActiveSessions = try container.decodeIfPresent(Int.self, forKey: .maxActiveSessions)
        self.maxParentalRating = try container.decodeIfPresent(Int.self, forKey: .maxParentalRating)
        self.maxParentalSubRating = try container.decodeIfPresent(Int.self, forKey: .maxParentalSubRating)
        self.passwordResetProviderID = try container.decodeIfPresent(String.self, forKey: .passwordResetProviderID) ?? ""
        self.remoteClientBitrateLimit = try container.decodeIfPresent(Int.self, forKey: .remoteClientBitrateLimit)
        self.syncPlayAccess = try container.decodeIfPresent(SyncPlayUserAccessType.self, forKey: .syncPlayAccess)
    }
}

struct AccessSchedule: Codable, Hashable, Identifiable, Sendable {
    var dayOfWeek: DynamicDayOfWeek?
    var endHour: Double?
    var id: Int?
    var startHour: Double?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "DayOfWeek"
        case endHour = "EndHour"
        case id = "Id"
        case startHour = "StartHour"
        case userID = "UserId"
    }
}

enum DayOfWeek: String, Codable, CaseIterable, Sendable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
}

enum DynamicDayOfWeek: String, Codable, CaseIterable, Sendable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case everyday = "Everyday"
    case weekday = "Weekday"
    case weekend = "Weekend"
}

enum UnratedItem: String, Codable, CaseIterable, Sendable {
    case movie = "Movie"
    case trailer = "Trailer"
    case series = "Series"
    case music = "Music"
    case book = "Book"
    case liveTvChannel = "LiveTvChannel"
    case liveTvProgram = "LiveTvProgram"
    case channelContent = "ChannelContent"
    case other = "Other"
}

enum SyncPlayUserAccessType: String, Codable, CaseIterable, Sendable {
    case createAndJoinGroups = "CreateAndJoinGroups"
    case joinGroups = "JoinGroups"
    case none = "None"
}

enum SubtitlePlaybackMode: String, Codable, CaseIterable, Sendable {
    case `default` = "Default"
    case always = "Always"
    case onlyForced = "OnlyForced"
    case none = "None"
    case smart = "Smart"
}

enum EmbyPortDateCodec {
    static func parse(_ value: String) -> Date? {
        fractionalSeconds.date(from: value) ?? plain.date(from: value)
    }

    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = parse(value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid Emby ISO-8601 date: \(value)"
        )
    }

    static func encode(_ date: Date, encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string(from: date))
    }

    static func string(from date: Date) -> String {
        fractionalSeconds.string(from: date)
    }

    private static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    func decodeEmbyDateIfPresent(forKey key: Key) throws -> Date? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return EmbyPortDateCodec.parse(value)
        }

        return try decodeIfPresent(Date.self, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeEmbyDateIfPresent(_ date: Date?, forKey key: Key) throws {
        guard let date else { return }
        try encode(EmbyPortDateCodec.string(from: date), forKey: key)
    }
}
