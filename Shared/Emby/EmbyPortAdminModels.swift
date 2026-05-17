//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum MetadataRefreshMode: String, Codable, Hashable, Sendable {
    case `default` = "Default"
    case fullRefresh = "FullRefresh"
}

struct PublicSystemInfo: Codable, Hashable, Sendable {
    var id: String? = nil
    var serverName: String? = nil
    var version: String? = nil

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
    }
}

struct EmbyAPIKey: Decodable, Hashable {
    var appName: String?
    var accessToken: String?
    var dateCreated: Date?

    enum CodingKeys: String, CodingKey {
        case appName = "AppName"
        case accessToken = "AccessToken"
        case dateCreated = "DateCreated"
    }

    init(appName: String? = nil, accessToken: String? = nil, dateCreated: Date? = nil) {
        self.appName = appName
        self.accessToken = accessToken
        self.dateCreated = dateCreated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.appName = try container.decodeIfPresent(String.self, forKey: .appName)
        self.accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)

        self.dateCreated = try container.decodeIfPresent(String.self, forKey: .dateCreated).flatMap(EmbyPortDateParser.parse)
    }
}

struct EmbyLogFile: Decodable, Hashable {
    var name: String?
    var dateModified: Date

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case dateModified = "DateModified"
    }

    init(name: String? = nil, dateModified: Date = .distantPast) {
        self.name = name
        self.dateModified = dateModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.dateModified = try container.decodeIfPresent(String.self, forKey: .dateModified)
            .flatMap(EmbyPortDateParser.parse) ?? .distantPast
    }
}

struct EmbyDeviceInfo: Decodable, Hashable {
    var id: String?
    var name: String?
    var customName: String?
    var appName: String?
    var appVersion: String?
    var dateLastActivity: Date
    var lastUserID: String?
    var lastUserName: String?
    var capabilities: EmbyDeviceCapabilities?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case customName = "CustomName"
        case appName = "AppName"
        case appVersion = "AppVersion"
        case dateLastActivity = "DateLastActivity"
        case lastUserID = "LastUserId"
        case lastUserName = "LastUserName"
        case capabilities = "Capabilities"
    }

    init(
        id: String? = nil,
        name: String? = nil,
        customName: String? = nil,
        appName: String? = nil,
        appVersion: String? = nil,
        dateLastActivity: Date = .distantPast,
        lastUserID: String? = nil,
        lastUserName: String? = nil,
        capabilities: EmbyDeviceCapabilities? = nil
    ) {
        self.id = id
        self.name = name
        self.customName = customName
        self.appName = appName
        self.appVersion = appVersion
        self.dateLastActivity = dateLastActivity
        self.lastUserID = lastUserID
        self.lastUserName = lastUserName
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.customName = try container.decodeIfPresent(String.self, forKey: .customName)
        self.appName = try container.decodeIfPresent(String.self, forKey: .appName)
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        self.dateLastActivity = try container.decodeIfPresent(String.self, forKey: .dateLastActivity)
            .flatMap(EmbyPortDateParser.parse) ?? .distantPast
        self.lastUserID = try container.decodeIfPresent(String.self, forKey: .lastUserID)
        self.lastUserName = try container.decodeIfPresent(String.self, forKey: .lastUserName)
        self.capabilities = try container.decodeIfPresent(EmbyDeviceCapabilities.self, forKey: .capabilities)
    }
}

struct EmbyDeviceCapabilities: Decodable, Hashable {
    var isSupportsMediaControl: Bool?
    var isSupportsPersistentIdentifier: Bool?

    enum CodingKeys: String, CodingKey {
        case isSupportsMediaControl = "SupportsMediaControl"
        case isSupportsPersistentIdentifier = "SupportsPersistentIdentifier"
    }
}

struct EmbyDeviceOptions: Encodable, Hashable {
    var customName: String?

    enum CodingKeys: String, CodingKey {
        case customName = "CustomName"
    }
}

struct EmbyActivityLogEntry: Decodable, Hashable, Identifiable {
    var id: Int?
    var name: String?
    var overview: String?
    var shortOverview: String?
    var type: String?
    var itemID: String?
    var userID: String?
    var date: Date?
    var severity: EmbyLogLevel?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case shortOverview = "ShortOverview"
        case type = "Type"
        case itemID = "ItemId"
        case userID = "UserId"
        case date = "Date"
        case severity = "Severity"
    }

    init(
        id: Int? = nil,
        name: String? = nil,
        overview: String? = nil,
        shortOverview: String? = nil,
        type: String? = nil,
        itemID: String? = nil,
        userID: String? = nil,
        date: Date? = nil,
        severity: EmbyLogLevel? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.shortOverview = shortOverview
        self.type = type
        self.itemID = itemID
        self.userID = userID
        self.date = date
        self.severity = severity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIntLikeValueIfPresent(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.overview = try container.decodeIfPresent(String.self, forKey: .overview)
        self.shortOverview = try container.decodeIfPresent(String.self, forKey: .shortOverview)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
        self.userID = try container.decodeIfPresent(String.self, forKey: .userID)
        self.date = try container.decodeIfPresent(String.self, forKey: .date).flatMap(EmbyPortDateParser.parse)
        self.severity = try container.decodeIfPresent(EmbyLogLevel.self, forKey: .severity)
    }
}

enum EmbyLogLevel: String, Codable, CaseIterable, Hashable {
    case trace = "Trace"
    case debug = "Debug"
    case information = "Information"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"
    case none = "None"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? .none
    }
}

struct EmbyTaskInfo: Decodable, Hashable {
    var id: String?
    var name: String?
    var description: String?
    var category: String?
    var state: EmbyTaskState?
    var currentProgressPercentage: Double?
    var lastExecutionResult: EmbyTaskExecutionResult?
    var triggers: [EmbyTaskTrigger]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case description = "Description"
        case category = "Category"
        case state = "State"
        case currentProgressPercentage = "CurrentProgressPercentage"
        case lastExecutionResult = "LastExecutionResult"
        case triggers = "Triggers"
    }
}

struct EmbyTaskExecutionResult: Decodable, Hashable {
    var endTimeUtc: Date?
    var status: EmbyTaskCompletionStatus?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case endTimeUtc = "EndTimeUtc"
        case status = "Status"
        case errorMessage = "ErrorMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.endTimeUtc = try container.decodeIfPresent(String.self, forKey: .endTimeUtc).flatMap(EmbyPortDateParser.parse)
        self.status = try container.decodeIfPresent(EmbyTaskCompletionStatus.self, forKey: .status)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

struct EmbyTaskTrigger: Codable, Hashable {
    var dayOfWeek: EmbyTaskDayOfWeek?
    var intervalTicks: Int?
    var maxRuntimeTicks: Int?
    var timeOfDayTicks: Int?
    var type: EmbyTaskTriggerType?

    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "DayOfWeek"
        case intervalTicks = "IntervalTicks"
        case maxRuntimeTicks = "MaxRuntimeTicks"
        case timeOfDayTicks = "TimeOfDayTicks"
        case type = "Type"
    }
}

enum EmbyTaskState: String, Codable, CaseIterable, Hashable {
    case cancelling = "Cancelling"
    case idle = "Idle"
    case running = "Running"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? .idle
    }
}

enum EmbyTaskCompletionStatus: String, Codable, CaseIterable, Hashable {
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case aborted = "Aborted"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? .failed
    }
}

enum EmbyTaskTriggerType: String, Codable, CaseIterable, Hashable {
    case dailyTrigger = "DailyTrigger"
    case weeklyTrigger = "WeeklyTrigger"
    case intervalTrigger = "IntervalTrigger"
    case startupTrigger = "StartupTrigger"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? .startupTrigger
    }
}

enum EmbyTaskDayOfWeek: String, Codable, CaseIterable, Hashable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? .sunday
    }
}

private enum EmbyPortDateParser {
    static func parse(_ value: String) -> Date? {
        dateFormatterWithFractionalSeconds.date(from: value) ?? dateFormatter.date(from: value)
    }

    private static let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    func decodeIntLikeValueIfPresent(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }
}
