//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct EmbyPortClientIdentity: Equatable, Sendable {
    var clientName: String
    var deviceName: String
    var deviceID: String
    var version: String

    init(
        clientName: String,
        deviceName: String,
        deviceID: String,
        version: String
    ) {
        self.clientName = clientName
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.version = version
    }

    static func embyDefault() -> EmbyPortClientIdentity {
        EmbyPortClientIdentity(
            clientName: "Emby iOS Player",
            deviceName: currentDeviceName,
            deviceID: persistedDeviceID,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        )
    }

    private static var currentDeviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Apple"
        #endif
    }

    private static var persistedDeviceID: String {
        let key = "EmbyIOSPlayerDeviceID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}

struct EmbyPortServerInfo: Equatable, Sendable {
    var id: String
    var name: String
    var version: String?
}

struct EmbyPortUser: Equatable, Sendable {
    var id: String
    var name: String
}

struct EmbyPortAuthenticatedSession: Equatable, Sendable {
    var serverID: String?
    var accessToken: String
    var user: EmbyPortUser
}

struct EmbyPortItemsResponse<Item: Decodable>: Decodable {
    var items: [Item]?
    var totalRecordCount: Int?
    var startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

struct EmbyPortCurrentUserResponse: Decodable {
    var configuration: Configuration?

    struct Configuration: Decodable {
        var latestItemsExcludes: [String]?
        var myMediaExcludes: [String]?

        enum CodingKeys: String, CodingKey {
            case latestItemsExcludes = "LatestItemsExcludes"
            case myMediaExcludes = "MyMediaExcludes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case configuration = "Configuration"
    }
}

struct EmbyPortDownloadResponse {
    var value: URL
    var response: URLResponse
}

struct EmbyPortQueryFiltersResponse: Decodable {
    var genres: [String]?
    var studios: [NameGuidPair]?
    var tags: [String]?
    var years: [Int]?

    enum CodingKeys: String, CodingKey {
        case genres = "Genres"
        case studios = "Studios"
        case tags = "Tags"
        case years = "Years"
    }

    init(
        genres: [String]? = nil,
        studios: [NameGuidPair]? = nil,
        tags: [String]? = nil,
        years: [Int]? = nil
    ) {
        self.genres = genres
        self.studios = studios
        self.tags = tags
        self.years = years
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        years = try container.decodeIfPresent([Int].self, forKey: .years)

        if let decodedStudios = try? container.decodeIfPresent([NameGuidPair].self, forKey: .studios) {
            studios = decodedStudios
        } else {
            studios = try container.decodeIfPresent([String].self, forKey: .studios)?
                .map { NameGuidPair(id: $0, name: $0) }
        }
    }
}

struct EmbyPortSessionConfiguration: Equatable, Sendable {
    var baseURL: URL
    var accessToken: String
    var userID: String
    var identity: EmbyPortClientIdentity
}

enum EmbyPortAPIError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Emby 服务器地址无效"
        case .invalidResponse:
            "Emby 服务器响应无效"
        case let .httpStatus(statusCode):
            "Emby 请求失败，HTTP \(statusCode)"
        }
    }
}

protocol EmbyPortHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class EmbyPortURLSessionTransport: EmbyPortHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbyPortAPIError.invalidResponse
        }
        return (data, httpResponse)
    }
}

final class EmbyPortAuthenticationClient: @unchecked Sendable {
    let baseURL: URL

    private let identity: EmbyPortClientIdentity
    private let transport: EmbyPortHTTPTransport
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try EmbyPortDateCodec.decode(decoder)
        }
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            try EmbyPortDateCodec.encode(date, encoder: encoder)
        }
        return encoder
    }()

    init(
        baseURL: URL,
        identity: EmbyPortClientIdentity,
        transport: EmbyPortHTTPTransport = EmbyPortURLSessionTransport()
    ) {
        self.baseURL = baseURL
        self.identity = identity
        self.transport = transport
    }

    func publicSystemInfo() async throws -> (info: EmbyPortServerInfo, responseURL: URL?) {
        let (dto, response): (EmbyPortPublicSystemInfoDTO, HTTPURLResponse) = try await send(path: "/System/Info/Public")
        guard let id = dto.id, let name = dto.serverName else {
            throw EmbyPortAPIError.invalidResponse
        }

        return (
            EmbyPortServerInfo(id: id, name: name, version: dto.version),
            response.url
        )
    }

    func authenticate(username: String, password: String) async throws -> EmbyPortAuthenticatedSession {
        let body = EmbyPortAuthenticateByNameDTO(username: username, password: password)
        let (dto, _): (EmbyPortAuthenticationResultDTO, HTTPURLResponse) = try await send(
            path: "/Users/AuthenticateByName",
            method: "POST",
            body: body
        )

        guard let accessToken = dto.accessToken,
              let id = dto.user?.id,
              let name = dto.user?.name
        else {
            throw EmbyPortAPIError.invalidResponse
        }

        return EmbyPortAuthenticatedSession(
            serverID: dto.serverID,
            accessToken: accessToken,
            user: EmbyPortUser(id: id, name: name)
        )
    }

    func publicUsers() async throws -> [EmbyPortUser] {
        let (users, _): ([EmbyPortUserDTO], HTTPURLResponse) = try await send(path: "/Users/Public")
        return users.compactMap { user in
            guard let id = user.id, let name = user.name else { return nil }
            return EmbyPortUser(id: id, name: name)
        }
    }

    func loginDisclaimer() async throws -> String? {
        let (branding, _): (EmbyPortBrandingDTO, HTTPURLResponse) = try await send(path: "/Branding/Configuration")
        guard let disclaimer = branding.loginDisclaimer, !disclaimer.isEmpty else { return nil }
        return disclaimer
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> (Response, HTTPURLResponse) {
        let request = try makeRequest(path: path, method: method)
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return (try decoder.decode(Response.self, from: data), response)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: some Encodable
    ) async throws -> (Response, HTTPURLResponse) {
        var request = try makeRequest(path: path, method: method)
        request.httpBody = try encoder.encode(EmbyPortAnyEncodable(body))
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return (try decoder.decode(Response.self, from: data), response)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw EmbyPortAPIError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")

        guard let url = components.url else {
            throw EmbyPortAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        return request
    }

    private var authorizationHeader: String {
        let client = identity.clientName.embyPortHeaderEscaped
        let device = identity.deviceName.embyPortHeaderEscaped
        let deviceID = identity.deviceID.embyPortHeaderEscaped
        let version = identity.version.embyPortHeaderEscaped
        return "MediaBrowser Client=\"\(client)\", Device=\"\(device)\", DeviceId=\"\(deviceID)\", Version=\"\(version)\""
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard 200..<300 ~= response.statusCode else {
            throw EmbyPortAPIError.httpStatus(response.statusCode)
        }
    }
}

final class EmbyPortSessionClient: @unchecked Sendable {
    let configuration: EmbyPortSessionConfiguration

    private let transport: EmbyPortHTTPTransport
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try EmbyPortDateCodec.decode(decoder)
        }
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            try EmbyPortDateCodec.encode(date, encoder: encoder)
        }
        return encoder
    }()

    init(
        configuration: EmbyPortSessionConfiguration,
        transport: EmbyPortHTTPTransport = EmbyPortURLSessionTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: some Encodable
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        request.httpBody = try encoder.encode(EmbyPortAnyEncodable(body))
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    func sendEmpty(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<EmbyPortEmptyBody>.none
    ) async throws {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        if let body {
            request.httpBody = try encoder.encode(EmbyPortAnyEncodable(body))
        }
        let (_, response) = try await transport.data(for: request)
        try validate(response)
    }

    func sendRaw(
        path: String,
        method: String,
        contentType: String,
        body: Data
    ) async throws {
        var request = try makeRequest(path: path, method: method)
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await transport.data(for: request)
        try validate(response)
    }

    func data(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(path: path, queryItems: queryItems)
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return data
    }

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in playbackHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return data
    }

    func download(
        path: String,
        queryItems: [URLQueryItem] = [],
        delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> EmbyPortDownloadResponse {
        let request = try makeRequest(path: path, queryItems: queryItems)
        let (url, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbyPortAPIError.invalidResponse
        }
        try validate(httpResponse)
        return EmbyPortDownloadResponse(value: url, response: response)
    }

    func download(
        from url: URL,
        delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> EmbyPortDownloadResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in playbackHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (url, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbyPortAPIError.invalidResponse
        }
        try validate(httpResponse)
        return EmbyPortDownloadResponse(value: url, response: response)
    }

    func resumeItems<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(
            path: "/Users/\(configuration.userID)/Items/Resume",
            queryItems: [
                URLQueryItem(name: "MediaTypes", value: "Video"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "EnableUserData", value: "true"),
                URLQueryItem(name: "SortBy", value: "DatePlayed"),
                URLQueryItem(name: "SortOrder", value: "Descending"),
                URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio,MediaSources")
            ]
        )
    }

    func resumeItems<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Users/\(configuration.userID)/Items/Resume",
            queryItems: queryItems
        )
    }

    func userViews<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Users/\(configuration.userID)/Views")
    }

    func currentUser<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Users/\(configuration.userID)")
    }

    func cultures<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Localization/Cultures")
    }

    func countries<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Localization/Countries")
    }

    func parentalRatings<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Localization/ParentalRatings")
    }

    func queryFilters<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/Filters",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func genres<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Genres",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func tags<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Tags",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func years<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Years",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func studios<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Studios",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func items<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Users/\(configuration.userID)/Items",
            queryItems: queryItems
        )
    }

    func item<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Users/\(configuration.userID)/Items/\(itemID)")
    }

    func itemImageInfos<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Items/\(itemID)/Images")
    }

    func remoteImages<Response: Decodable>(
        itemID: String,
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/\(itemID)/RemoteImages",
            queryItems: queryItems
        )
    }

    func downloadRemoteImage(
        itemID: String,
        imageType: Any,
        imageURL: String
    ) async throws {
        try await sendEmpty(
            path: "/Items/\(itemID)/RemoteImages/Download",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "Type", value: EmbyPortQueryItemBuilder.serializedQueryValue(imageType)),
                URLQueryItem(name: "ImageUrl", value: imageURL)
            ]
        )
    }

    func setItemImage(
        itemID: String,
        imageType: String,
        contentType: String,
        imageData: Data
    ) async throws {
        try await sendRaw(
            path: "/Items/\(itemID)/Images/\(imageType)",
            method: "POST",
            contentType: contentType,
            body: imageData.base64EncodedData()
        )
    }

    func deleteItemImage(
        itemID: String,
        imageType: String,
        imageIndex: Int? = nil
    ) async throws {
        var path = "/Items/\(itemID)/Images/\(imageType)"
        if let imageIndex {
            path += "/\(imageIndex)"
        }

        try await sendEmpty(path: path, method: "DELETE")
    }

    func deleteItem(itemID: String) async throws {
        try await sendEmpty(path: "/Items/\(itemID)", method: "DELETE")
    }

    func refreshItem(
        itemID: String,
        metadataRefreshMode: Any,
        imageRefreshMode: Any,
        replaceMetadata: Bool,
        replaceImages: Bool,
        regenerateTrickplay: Bool
    ) async throws {
        try await sendEmpty(
            path: "/Items/\(itemID)/Refresh",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "MetadataRefreshMode", value: EmbyPortQueryItemBuilder.serializedQueryValue(metadataRefreshMode)),
                URLQueryItem(name: "ImageRefreshMode", value: EmbyPortQueryItemBuilder.serializedQueryValue(imageRefreshMode)),
                URLQueryItem(name: "ReplaceAllMetadata", value: replaceMetadata ? "true" : "false"),
                URLQueryItem(name: "ReplaceAllImages", value: replaceImages ? "true" : "false"),
                URLQueryItem(name: "RegenerateTrickplay", value: regenerateTrickplay ? "true" : "false")
            ]
        )
    }

    func updateItem(itemID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Items/\(itemID)",
            method: "POST",
            body: body
        )
    }

    func sessions<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Sessions", queryItems: queryItems)
    }

    func serverLogs<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/System/Logs")
    }

    func devices<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Devices")
    }

    func updateDeviceOptions(id: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Devices/Options",
            method: "POST",
            queryItems: [URLQueryItem(name: "Id", value: id)],
            body: body
        )
    }

    func deleteDevice(id: String) async throws {
        try await sendEmpty(
            path: "/Devices",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "Id", value: id)]
        )
    }

    func apiKeys<Response: Decodable>(as type: Response.Type) async throws -> Response {
        try await send(path: "/Auth/Keys")
    }

    func createAPIKey(appName: String) async throws {
        try await sendEmpty(
            path: "/Auth/Keys",
            method: "POST",
            queryItems: [URLQueryItem(name: "App", value: appName)]
        )
    }

    func revokeAPIKey(accessToken: String) async throws {
        try await sendEmpty(path: "/Auth/Keys/\(accessToken)", method: "DELETE")
    }

    func activityLogEntries<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/System/ActivityLog/Entries",
            queryItems: queryItems
        )
    }

    func users<Response: Decodable>(
        queryItems: [URLQueryItem] = [],
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Users", queryItems: queryItems)
    }

    func user<Response: Decodable>(
        userID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Users/\(userID)")
    }

    func deleteUser(userID: String) async throws {
        try await sendEmpty(path: "/Users/\(userID)", method: "DELETE")
    }

    func updateUser(userID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Users/\(userID)",
            method: "POST",
            body: body
        )
    }

    func updateUserPolicy(userID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Users/\(userID)/Policy",
            method: "POST",
            body: body
        )
    }

    func updateUserConfiguration(userID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Users/\(userID)/Configuration",
            method: "POST",
            body: body
        )
    }

    func itemByID<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Items/\(itemID)")
    }

    func mediaFolders<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Library/MediaFolders", queryItems: queryItems)
    }

    func tasks<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/ScheduledTasks", queryItems: queryItems)
    }

    func task<Response: Decodable>(
        taskID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/ScheduledTasks/\(taskID)")
    }

    func startTask(taskID: String) async throws {
        try await sendEmpty(path: "/ScheduledTasks/Running/\(taskID)", method: "POST")
    }

    func stopTask(taskID: String) async throws {
        try await sendEmpty(path: "/ScheduledTasks/Running/\(taskID)", method: "DELETE")
    }

    func updateTaskTriggers(taskID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/ScheduledTasks/\(taskID)/Triggers",
            method: "POST",
            body: body
        )
    }

    func restartApplication() async throws {
        try await sendEmpty(path: "/System/Restart", method: "POST")
    }

    func shutdownApplication() async throws {
        try await sendEmpty(path: "/System/Shutdown", method: "POST")
    }

    func latestItems<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Users/\(configuration.userID)/Items/Latest",
            queryItems: queryItems
        )
    }

    func liveTVChannels<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/LiveTv/Channels",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func liveTVPrograms<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/LiveTv/Programs",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func recommendedPrograms<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/LiveTv/Programs/Recommended",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func nextUp<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Shows/NextUp",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func episodes<Response: Decodable>(
        seriesID: String,
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Shows/\(seriesID)/Episodes",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func seasons<Response: Decodable>(
        seriesID: String,
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Shows/\(seriesID)/Seasons",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func persons<Response: Decodable>(
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Persons",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func similarItems<Response: Decodable>(
        itemID: String,
        queryItems: [URLQueryItem],
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/\(itemID)/Similar",
            queryItems: addingUserID(to: queryItems)
        )
    }

    func specialFeatures<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/\(itemID)/SpecialFeatures",
            queryItems: [URLQueryItem(name: "UserId", value: configuration.userID)]
        )
    }

    func localTrailers<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Users/\(configuration.userID)/Items/\(itemID)/LocalTrailers"
        )
    }

    func additionalParts<Response: Decodable>(
        itemID: String,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Videos/\(itemID)/AdditionalParts")
    }

    func searchRemoteSubtitles<Response: Decodable>(
        itemID: String,
        language: String,
        isPerfectMatch: Bool,
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/\(itemID)/RemoteSearch/Subtitles/\(language)",
            queryItems: [URLQueryItem(name: "IsPerfectMatch", value: isPerfectMatch ? "true" : "false")]
        )
    }

    func downloadRemoteSubtitle(itemID: String, subtitleID: String) async throws {
        try await sendEmpty(
            path: "/Items/\(itemID)/RemoteSearch/Subtitles/\(subtitleID)",
            method: "POST"
        )
    }

    func uploadSubtitle(itemID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Videos/\(itemID)/Subtitles",
            method: "POST",
            body: body
        )
    }

    func deleteSubtitle(itemID: String, index: Int) async throws {
        try await sendEmpty(
            path: "/Videos/\(itemID)/Subtitles/\(index)",
            method: "DELETE"
        )
    }

    func remoteSearchResults<Response: Decodable>(
        itemType: String,
        body: some Encodable,
        as type: Response.Type
    ) async throws -> Response {
        try await send(
            path: "/Items/RemoteSearch/\(itemType)",
            method: "POST",
            body: body
        )
    }

    func applyRemoteSearchResult(itemID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Items/RemoteSearch/Apply/\(itemID)",
            method: "POST",
            body: body
        )
    }

    func trickplayTileImageData(
        itemID: String,
        width: Int,
        index: Int
    ) async throws -> Data {
        try await data(path: "/Videos/\(itemID)/Trickplay/\(width)/\(index).jpg")
    }

    func bitrateTestData(size: Int) async throws -> Data {
        try await data(
            path: "/Playback/BitrateTest",
            queryItems: [URLQueryItem(name: "Size", value: String(size))]
        )
    }

    func setPlayed(_ isPlayed: Bool, itemID: String) async throws {
        try await sendEmpty(
            path: "/Users/\(configuration.userID)/PlayedItems/\(itemID)",
            method: isPlayed ? "POST" : "DELETE"
        )
    }

    func setFavorite(_ isFavorite: Bool, itemID: String) async throws {
        try await sendEmpty(
            path: "/Users/\(configuration.userID)/FavoriteItems/\(itemID)",
            method: isFavorite ? "POST" : "DELETE"
        )
    }

    func reportPlaybackStarted(
        itemID: String?,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int64?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) async throws {
        try await sendEmpty(
            path: "/Sessions/Playing",
            method: "POST",
            body: EmbyPortPlaybackStartBody(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )
        )
    }

    func reportPlaybackProgress(
        itemID: String?,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int64?,
        isPaused: Bool,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) async throws {
        try await sendEmpty(
            path: "/Sessions/Playing/Progress",
            method: "POST",
            body: EmbyPortPlaybackProgressBody(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks,
                isPaused: isPaused,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )
        )
    }

    func reportPlaybackStopped(
        itemID: String?,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int64?
    ) async throws {
        try await sendEmpty(
            path: "/Sessions/Playing/Stopped",
            method: "POST",
            body: EmbyPortPlaybackStopBody(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks
            )
        )
    }

    func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw EmbyPortAPIError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw EmbyPortAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in playbackHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func absoluteURL(forPathOrURL value: String) -> URL? {
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }

        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relative = value.hasPrefix("/") ? value : "/\(value)"
        return URL(string: base + relative)
    }

    var playbackHeaders: [String: String] {
        [
            "X-Emby-Token": configuration.accessToken,
            "X-MediaBrowser-Token": configuration.accessToken,
            "X-Emby-Authorization": authorizationHeader(includeToken: true)
        ]
    }

    func itemImageURL(
        itemID: String,
        imageType: String,
        imageIndex: Int? = nil,
        maxWidth: Double? = nil,
        maxHeight: Double? = nil,
        quality: Int? = nil,
        tag: String? = nil,
        format: String? = nil
    ) -> URL? {
        var path = "/Items/\(itemID)/Images/\(imageType)"
        if let imageIndex {
            path += "/\(imageIndex)"
        }

        var queryItems: [URLQueryItem] = []
        if let maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: String(Int(maxWidth))))
        }
        if let maxHeight {
            queryItems.append(URLQueryItem(name: "maxHeight", value: String(Int(maxHeight))))
        }
        if let quality {
            queryItems.append(URLQueryItem(name: "quality", value: String(quality)))
        }
        if let tag {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        if let format {
            queryItems.append(URLQueryItem(name: "format", value: format))
        }

        return try? makeRequest(path: path, queryItems: queryItems).url
    }

    func userImageURL(
        userID: String? = nil,
        maxWidth: Double? = nil,
        maxHeight: Double? = nil,
        quality: Int? = nil
    ) -> URL? {
        var queryItems: [URLQueryItem] = []
        if let maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: String(Int(maxWidth))))
        }
        if let maxHeight {
            queryItems.append(URLQueryItem(name: "maxHeight", value: String(Int(maxHeight))))
        }
        if let quality {
            queryItems.append(URLQueryItem(name: "quality", value: String(quality)))
        }

        return try? makeRequest(
            path: "/Users/\(userID ?? configuration.userID)/Images/Primary",
            queryItems: queryItems
        ).url
    }

    func logFileURL(name: String) -> URL? {
        try? makeRequest(
            path: "/System/Logs/Log",
            queryItems: [
                URLQueryItem(name: "Name", value: name),
                URLQueryItem(name: "api_key", value: configuration.accessToken)
            ]
        ).url
    }

    func splashscreenURL() -> URL? {
        try? makeRequest(path: "/Branding/Splashscreen").url
    }

    func uploadUserImage(
        userID: String? = nil,
        contentType: String,
        imageData: Data
    ) async throws {
        try await sendRaw(
            path: "/Users/\(userID ?? configuration.userID)/Images/Primary",
            method: "POST",
            contentType: contentType,
            body: imageData
        )
    }

    func deleteUserImage(userID: String? = nil) async throws {
        try await sendEmpty(
            path: "/Users/\(userID ?? configuration.userID)/Images/Primary",
            method: "DELETE"
        )
    }

    func createUser<Response: Decodable>(
        body: some Encodable,
        as type: Response.Type
    ) async throws -> Response {
        try await send(path: "/Users/New", method: "POST", body: body)
    }

    func updateUserPassword(userID: String, body: some Encodable) async throws {
        try await sendEmpty(
            path: "/Users/\(userID)/Password",
            method: "POST",
            body: body
        )
    }

    func videoStreamURL(
        itemID: String,
        mediaSourceID: String?,
        playSessionID: String?,
        tag: String?
    ) -> URL? {
        var queryItems = [URLQueryItem(name: "static", value: "true")]
        if let mediaSourceID {
            queryItems.append(URLQueryItem(name: "mediaSourceId", value: mediaSourceID))
        }
        if let playSessionID {
            queryItems.append(URLQueryItem(name: "PlaySessionId", value: playSessionID))
        }
        if let tag {
            queryItems.append(URLQueryItem(name: "Tag", value: tag))
        }

        return try? makeRequest(path: "/Videos/\(itemID)/stream", queryItems: queryItems).url
    }

    func subtitleStreamURL(
        itemID: String,
        mediaSourceID: String,
        streamIndex: Int,
        format: String
    ) -> URL? {
        subtitleStreamURLs(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            streamIndex: streamIndex,
            format: format
        ).first
    }

    func subtitleStreamURLs(
        itemID: String,
        mediaSourceID: String,
        streamIndex: Int,
        format: String
    ) -> [URL] {
        let endpoint = "/Videos/\(itemID)/Subtitles/\(streamIndex)/Stream.\(format)"
        let candidates: [(path: String, queryItems: [URLQueryItem])] = [
            (
                "/Videos/\(itemID)/\(mediaSourceID)/Subtitles/\(streamIndex)/Stream.\(format)",
                []
            ),
            (
                endpoint,
                [URLQueryItem(name: "MediaSourceId", value: mediaSourceID)]
            ),
            (
                endpoint,
                [URLQueryItem(name: "mediaSourceId", value: mediaSourceID)]
            ),
            (
                endpoint,
                []
            ),
        ]

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let url = try? makeRequest(path: candidate.path, queryItems: candidate.queryItems).url else {
                return nil
            }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    private func authorizationHeader(includeToken: Bool) -> String {
        let client = configuration.identity.clientName.embyPortHeaderEscaped
        let device = configuration.identity.deviceName.embyPortHeaderEscaped
        let deviceID = configuration.identity.deviceID.embyPortHeaderEscaped
        let version = configuration.identity.version.embyPortHeaderEscaped
        var parts = [
            "Client=\"\(client)\"",
            "Device=\"\(device)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(version)\""
        ]
        if includeToken {
            parts.append("Token=\"\(configuration.accessToken.embyPortHeaderEscaped)\"")
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func addingUserID(to queryItems: [URLQueryItem]) -> [URLQueryItem] {
        if queryItems.contains(where: { $0.name.caseInsensitiveCompare("UserId") == .orderedSame }) {
            return queryItems
        }

        return queryItems + [URLQueryItem(name: "UserId", value: configuration.userID)]
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard 200..<300 ~= response.statusCode else {
            throw EmbyPortAPIError.httpStatus(response.statusCode)
        }
    }
}

enum EmbyPortQueryItemBuilder {
    static func queryItems(
        from value: Any,
        keyMap: [String: String] = defaultKeyMap
    ) -> [URLQueryItem] {
        Mirror(reflecting: value).children.compactMap { child -> URLQueryItem? in
            guard let label = child.label else { return nil }
            let name = keyMap[label] ?? label.embyPortPascalCase
            guard let serialized = serialize(child.value, arraySeparator: arraySeparator(for: name)) else { return nil }
            return URLQueryItem(name: name, value: serialized)
        }
    }

    static func serializedQueryValue(_ value: Any) -> String {
        serialize(value) ?? String(describing: value)
    }

    private static let defaultKeyMap: [String: String] = [
        "adjacentTo": "AdjacentTo",
        "channelIDs": "ChannelIds",
        "enableRewatching": "EnableRewatching",
        "enableUserData": "EnableUserData",
        "excludeItemIDs": "ExcludeItemIds",
        "fields": "Fields",
        "filters": "Filters",
        "genres": "Genres",
        "hasAired": "HasAired",
        "hasUserID": "HasUserId",
        "ids": "Ids",
        "includeItemTypes": "IncludeItemTypes",
        "isAiring": "IsAiring",
        "isDisabled": "IsDisabled",
        "isEnabled": "IsEnabled",
        "isHidden": "IsHidden",
        "isIncludeAllLanguages": "IncludeAllLanguages",
        "isKids": "IsKids",
        "isMissing": "IsMissing",
        "isMovie": "IsMovie",
        "isNews": "IsNews",
        "isPerfectMatch": "IsPerfectMatch",
        "isRecursive": "Recursive",
        "isSeries": "IsSeries",
        "isSports": "IsSports",
        "limit": "Limit",
        "nameLessThan": "NameLessThan",
        "nameStartsWith": "NameStartsWith",
        "nextUpDateCutoff": "NextUpDateCutoff",
        "parentID": "ParentId",
        "personIDs": "PersonIds",
        "providerName": "ProviderName",
        "activeWithinSeconds": "ActiveWithinSeconds",
        "minDate": "MinDate",
        "searchTerm": "SearchTerm",
        "seasonID": "SeasonId",
        "seriesID": "SeriesId",
        "sortBy": "SortBy",
        "sortOrder": "SortOrder",
        "startIndex": "StartIndex",
        "studioIDs": "StudioIds",
        "tags": "Tags",
        "userID": "UserId",
        "years": "Years",
    ]

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func serialize(_ value: Any, arraySeparator: String = ",") -> String? {
        guard let value = unwrapOptional(value) else { return nil }

        if let date = value as? Date {
            return iso8601Formatter.string(from: date)
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let string = value as? String {
            return string.isEmpty ? nil : string
        }

        if let rawRepresentable = value as? any RawRepresentable {
            return String(describing: rawRepresentable.rawValue)
        }

        if let array = value as? [Any] {
            return serializeArray(array, separator: arraySeparator)
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .collection || mirror.displayStyle == .set {
            return serializeArray(mirror.children.map(\.value), separator: arraySeparator)
        }

        return String(describing: value)
    }

    private static func serializeArray(_ values: [Any], separator: String) -> String? {
        let serialized = values.compactMap { serialize($0) }
        return serialized.isEmpty ? nil : serialized.joined(separator: separator)
    }

    private static func arraySeparator(for queryName: String) -> String {
        switch queryName {
        case "Albums", "Artists", "ArtistIds", "ExcludeTags", "Genres", "OfficialRatings", "StudioIds", "Studios", "Tags":
            "|"
        default:
            ","
        }
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }
}

private struct EmbyPortEmptyBody: Encodable {}

private struct EmbyPortPlaybackStartBody: Encodable {
    var itemID: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var positionTicks: Int64?
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
    }
}

private struct EmbyPortPlaybackProgressBody: Encodable {
    var itemID: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var positionTicks: Int64?
    var isPaused: Bool
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
    }
}

private struct EmbyPortPlaybackStopBody: Encodable {
    var itemID: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var positionTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
    }
}

private struct EmbyPortAnyEncodable: Encodable {
    private let encodeBody: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        self.encodeBody = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeBody(encoder)
    }
}

private struct EmbyPortPublicSystemInfoDTO: Decodable {
    var id: String?
    var serverName: String?
    var version: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
    }
}

private struct EmbyPortAuthenticateByNameDTO: Encodable {
    var username: String
    var password: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Pw"
    }
}

private struct EmbyPortAuthenticationResultDTO: Decodable {
    var accessToken: String?
    var serverID: String?
    var user: EmbyPortUserDTO?

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case serverID = "ServerId"
        case user = "User"
    }
}

private struct EmbyPortUserDTO: Decodable {
    var id: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

private struct EmbyPortBrandingDTO: Decodable {
    var loginDisclaimer: String?

    enum CodingKeys: String, CodingKey {
        case loginDisclaimer = "LoginDisclaimer"
    }
}

private extension String {
    var embyPortHeaderEscaped: String {
        replacingOccurrences(of: "\"", with: "")
    }

    var embyPortPascalCase: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
