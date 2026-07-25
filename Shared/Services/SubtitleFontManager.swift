//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import CoreText

enum SubtitleFontManager {

    struct RemoteFontEntry: Identifiable, Hashable {
        let path: String
        let name: String
        let isCompact: Bool

        var id: String { path }
    }

    struct RemoteFolder: Identifiable, Hashable {
        let path: String
        let name: String
        var id: String { path }
    }

    struct IndexProgress: Sendable {
        let scannedFolders: Int
        let indexedFonts: Int
    }

    private static let importedFontNamesKey = "subtitleFontManager.importedFontNames"
    private static let automaticDownloadKey = "subtitleFontManager.automaticDownload"
    private static let remoteServerURLKey = "subtitleFontManager.remoteServerURL"
    private static let remoteFoldersKey = "subtitleFontManager.remoteFolders"
    private static let remoteFolderURLKey = "subtitleFontManager.remoteFolderURL"
    private static let legacyRemoteBaseURLKey = "subtitleFontManager.remoteBaseURL"
    private static let defaultRemoteServerURL = ""
    private static let defaultRemoteFolder = "/6/超级字体整合包 XZ"
    fileprivate static let supportedExtensions = Set(["ttf", "otf", "ttc", "otc"])

    static var automaticDownloadEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: automaticDownloadKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: automaticDownloadKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: automaticDownloadKey) }
    }

    static var remoteServerURL: String {
        get {
            if let value = UserDefaults.standard.string(forKey: remoteServerURLKey), !value.isEmpty {
                return value
            }
            if let folderURL = UserDefaults.standard.string(forKey: remoteFolderURLKey),
               let components = URLComponents(string: folderURL),
               let scheme = components.scheme,
               let host = components.host
            {
                var origin = URLComponents()
                origin.scheme = scheme
                origin.host = host
                origin.port = components.port
                return origin.string ?? defaultRemoteServerURL
            }
            if let legacy = UserDefaults.standard.string(forKey: legacyRemoteBaseURLKey), !legacy.isEmpty {
                return legacy.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return defaultRemoteServerURL
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: remoteServerURLKey
            )
        }
    }

    static var remoteFontFolders: [String] {
        get {
            if let folders = UserDefaults.standard.stringArray(forKey: remoteFoldersKey) {
                return folders
            }
            if let folderURL = UserDefaults.standard.string(forKey: remoteFolderURLKey),
               let components = URLComponents(string: folderURL),
               !components.path.isEmpty,
               components.path != "/"
            {
                return [components.percentEncodedPath.removingPercentEncoding ?? components.path]
            }
            return [defaultRemoteFolder]
        }
        set { UserDefaults.standard.set(Array(Set(newValue)).sorted(), forKey: remoteFoldersKey) }
    }

    static var importedFonts: [URL] {
        let names = UserDefaults.standard.stringArray(forKey: importedFontNamesKey) ?? []
        return names
            .map { fontsDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult
    static func install(from sourceURLs: [URL], preferredName: String? = nil) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: fontsDirectory,
            withIntermediateDirectories: true
        )

        var importedNames = Set(UserDefaults.standard.stringArray(forKey: importedFontNamesKey) ?? [])
        var installed: [URL] = []

        for sourceURL in sourceURLs {
            let fileExtension = sourceURL.pathExtension.lowercased()
            guard supportedExtensions.contains(fileExtension) else {
                throw FontError.unsupportedFormat(sourceURL.lastPathComponent)
            }

            let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = fontsDirectory.appendingPathComponent(
                sourceURLs.count == 1 ? (preferredName ?? sourceURL.lastPathComponent) : sourceURL.lastPathComponent
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            importedNames.insert(destinationURL.lastPathComponent)
            installed.append(destinationURL)
        }

        UserDefaults.standard.set(importedNames.sorted(), forKey: importedFontNamesKey)
        return installed
    }

    static func remove(_ fontURL: URL) throws {
        var importedNames = Set(UserDefaults.standard.stringArray(forKey: importedFontNamesKey) ?? [])
        guard importedNames.contains(fontURL.lastPathComponent) else { return }

        if FileManager.default.fileExists(atPath: fontURL.path) {
            try FileManager.default.removeItem(at: fontURL)
        }
        importedNames.remove(fontURL.lastPathComponent)
        UserDefaults.standard.set(importedNames.sorted(), forKey: importedFontNamesKey)
    }

    static func loadStatus(
        for fontName: String,
        mediaStreams: [MediaStream]
    ) -> String {
        let requiredName = normalizedFontName(fontName)
        guard !requiredName.isEmpty else { return "缺失" }

        if installedFontNames.contains(where: { normalizedFontName($0) == requiredName }) {
            return "可加载"
        }

        let attachmentNames = mediaStreams
            .filter { $0.type == .attachment }
            .flatMap { stream in
                [stream.displayTitle, stream.title, stream.path?.lastPathComponent]
                    .compactMap { $0 }
            }
        if attachmentNames.contains(where: { attachmentName in
            let normalizedAttachment = normalizedFontName(
                URL(fileURLWithPath: attachmentName).deletingPathExtension().lastPathComponent
            )
            return normalizedAttachment == requiredName || normalizedAttachment.contains(requiredName)
        }) {
            return "可加载（内嵌）"
        }

        return "缺失"
    }

    static func ensureFonts(
        _ fontNames: [String],
        ignoringAutomaticDownloadSetting: Bool = false
    ) async {
        guard automaticDownloadEnabled || ignoringAutomaticDownloadSetting else { return }

        let missing = fontNames.filter { !isInstalled($0) }
        guard missing.isNotEmpty else { return }

        do {
            let index = try await RemoteFontRepository.shared.fontIndex()
            for fontName in missing where !Task.isCancelled {
                guard let candidates = index.candidates(for: fontName) else { continue }
                for candidate in candidates.prefix(8) {
                    guard !Task.isCancelled else { return }
                    if (try? await RemoteFontRepository.shared.downloadAndInstall(candidate, requiredName: fontName)) == true {
                        break
                    }
                }
            }
        } catch {
            #if DEBUG
            AppLog.event("SubtitleFontAutoDownload failed: %@", error.localizedDescription)
            #endif
        }
    }

    static func remoteFontEntries() async throws -> [RemoteFontEntry] {
        try await RemoteFontRepository.shared.fontIndex().files.map {
            RemoteFontEntry(path: $0.path, name: $0.name, isCompact: $0.isCompact)
        }
    }

    static func browseRemoteFolders(at path: String) async throws -> [RemoteFolder] {
        try await RemoteFontRepository.shared.folders(at: path).map {
            RemoteFolder(path: $0.path, name: $0.name)
        }
    }

    static func rebuildRemoteFontIndex(
        progress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws -> [RemoteFontEntry] {
        let index = try await RemoteFontRepository.shared.rebuildIndex(
            folders: remoteFontFolders,
            progress: progress
        )
        return index.files.map {
            RemoteFontEntry(path: $0.path, name: $0.name, isCompact: $0.isCompact)
        }
    }

    @discardableResult
    static func installRemoteFont(_ entry: RemoteFontEntry) async throws -> URL {
        try await RemoteFontRepository.shared.downloadAndInstall(
            .init(path: entry.path, name: entry.name, isCompact: entry.isCompact)
        )
    }

    static func isInstalled(_ fontName: String) -> Bool {
        let requiredName = normalizedFontName(fontName)
        return installedFontNames.contains { normalizedFontName($0) == requiredName }
    }

    static var installedFontNames: Set<String> {
        var urls = importedFonts
        if let bundledFontsURL = Bundle.main.url(forResource: "Fonts", withExtension: nil),
           let bundledURLs = try? FileManager.default.contentsOfDirectory(
               at: bundledFontsURL,
               includingPropertiesForKeys: nil,
               options: .skipsHiddenFiles
           ) {
            urls.append(contentsOf: bundledURLs)
        }
        if let bundledFontURL = Bundle.main.url(forResource: "NotoSansCJKsc-Regular", withExtension: "otf") {
            urls.append(bundledFontURL)
        }

        var names = Set<String>()
        for url in urls where supportedExtensions.contains(url.pathExtension.lowercased()) {
            names.insert(url.deletingPathExtension().lastPathComponent)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
                continue
            }
            for descriptor in descriptors {
                for attribute in [kCTFontFamilyNameAttribute, kCTFontDisplayNameAttribute, kCTFontNameAttribute] {
                    if let value = CTFontDescriptorCopyAttribute(descriptor, attribute) as? String {
                        names.insert(value)
                    }
                    var language: Unmanaged<CFString>?
                    if let localized = CTFontDescriptorCopyLocalizedAttribute(
                        descriptor,
                        attribute,
                        &language
                    ) as? String {
                        names.insert(localized)
                    }
                }
            }
        }
        return names
    }

    static func normalizedFontName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static var fontsDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("mpv", isDirectory: true)
            .appendingPathComponent("fonts", isDirectory: true)
    }

    enum FontError: LocalizedError {
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedFormat(name):
                "不支持字体文件：\(name)"
            }
        }
    }
}

private actor RemoteFontRepository {

    static let shared = RemoteFontRepository()

    private struct APIResponse<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let data: T?
    }

    private struct FileInfo: Decodable {
        let rawURL: URL

        enum CodingKeys: String, CodingKey {
            case rawURL = "raw_url"
        }
    }

    private struct ListData: Decodable {
        let content: [ListItem]?
    }

    private struct ListItem: Decodable {
        let name: String
        let isDir: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case isDir = "is_dir"
        }
    }

    struct Folder {
        let path: String
        let name: String
    }

    struct FontFile: Codable, Hashable {
        let path: String
        let name: String
        let isCompact: Bool
    }

    struct FontIndex: Codable {
        let files: [FontFile]

        func candidates(for fontName: String) -> [FontFile]? {
            let required = SubtitleFontManager.normalizedFontName(fontName)
            guard !required.isEmpty else { return nil }

            let matches = files.compactMap { file -> (FontFile, Int)? in
                let stem = URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent
                let normalized = SubtitleFontManager.normalizedFontName(stem)
                guard normalized == required || normalized.contains(required) || required.contains(normalized) else {
                    return nil
                }
                let score = (normalized == required ? 0 : 10) + (file.isCompact ? 0 : 100) + abs(normalized.count - required.count)
                return (file, score)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            return matches.isEmpty ? nil : matches
        }
    }

    private var memoryIndex: FontIndex?
    private var memoryCacheKey: String?

    private struct Source {
        let serverURL: String
        let getAPIURL: URL
        let listAPIURL: URL
    }

    func fontIndex() async throws -> FontIndex {
        let key = cacheKey
        if let memoryIndex, memoryCacheKey == key { return memoryIndex }
        if let data = try? Data(contentsOf: indexCacheURL),
           let cached = try? JSONDecoder().decode(FontIndex.self, from: data),
           cached.files.isNotEmpty
        {
            memoryIndex = cached
            memoryCacheKey = key
            return cached
        }
        throw RepositoryError.indexNotBuilt
    }

    func folders(at path: String) async throws -> [Folder] {
        try await list(path: path)
            .filter(\.isDir)
            .map { Folder(path: joined(path, $0.name), name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func rebuildIndex(
        folders: [String],
        progress: @escaping @Sendable (SubtitleFontManager.IndexProgress) -> Void
    ) async throws -> FontIndex {
        guard !folders.isEmpty else { throw RepositoryError.noFoldersSelected }
        _ = try sourceConfiguration()

        var queue = folders.map(normalizedPath)
        var queueIndex = 0
        var visited = Set<String>()
        var files: [FontFile] = []

        while queueIndex < queue.count {
            try Task.checkCancellation()
            let folder = queue[queueIndex]
            queueIndex += 1
            guard visited.insert(folder).inserted else { continue }
            let items = try await list(path: folder)
            for item in items {
                let path = joined(folder, item.name)
                if item.isDir {
                    queue.append(path)
                } else if SubtitleFontManager.supportedExtensions.contains(
                    URL(fileURLWithPath: item.name).pathExtension.lowercased()
                ) {
                    files.append(FontFile(
                        path: path,
                        name: item.name,
                        isCompact: path.components(separatedBy: "/").contains("精简包")
                    ))
                }
            }
            progress(.init(scannedFolders: visited.count, indexedFonts: files.count))
        }

        let index = FontIndex(files: Array(Set(files)).sorted { $0.path < $1.path })
        try FileManager.default.createDirectory(
            at: indexCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(index).write(to: indexCacheURL, options: .atomic)
        memoryIndex = index
        memoryCacheKey = cacheKey
        return index
    }

    func downloadAndInstall(_ file: FontFile, requiredName: String) async throws -> Bool {
        let url = try await rawURL(for: file.path)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try validate(response)

        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(URL(fileURLWithPath: file.name).pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }

        guard fontNames(in: stagedURL).contains(where: {
            SubtitleFontManager.normalizedFontName($0) == SubtitleFontManager.normalizedFontName(requiredName)
        }) else {
            return false
        }

        _ = try SubtitleFontManager.install(from: [stagedURL], preferredName: file.name)
        return true
    }

    func downloadAndInstall(_ file: FontFile) async throws -> URL {
        let url = try await rawURL(for: file.path)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try validate(response)

        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(URL(fileURLWithPath: file.name).pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }
        guard !fontNames(in: stagedURL).isEmpty else { throw RepositoryError.invalidFont }
        return try SubtitleFontManager.install(from: [stagedURL], preferredName: file.name)[0]
    }

    private func rawURL(for path: String) async throws -> URL {
        let endpoint = try sourceConfiguration().getAPIURL

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "password": ""])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let result = try JSONDecoder().decode(APIResponse<FileInfo>.self, from: data)
        guard result.code == 200, let url = result.data?.rawURL else {
            throw RepositoryError.server(result.message)
        }
        return url
    }

    private func list(path: String) async throws -> [ListItem] {
        var request = URLRequest(url: try sourceConfiguration().listAPIURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": normalizedPath(path),
            "password": "",
            "page": 1,
            "per_page": 0,
            "refresh": false,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let result = try JSONDecoder().decode(APIResponse<ListData>.self, from: data)
        guard result.code == 200 else { throw RepositoryError.server(result.message) }
        return result.data?.content ?? []
    }

    private func fontNames(in url: URL) -> Set<String> {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        return Set(descriptors.flatMap { descriptor in
            [kCTFontFamilyNameAttribute, kCTFontDisplayNameAttribute, kCTFontNameAttribute].flatMap { attribute in
                var result: [String] = []
                if let value = CTFontDescriptorCopyAttribute(descriptor, attribute) as? String {
                    result.append(value)
                }
                var language: Unmanaged<CFString>?
                if let localized = CTFontDescriptorCopyLocalizedAttribute(
                    descriptor,
                    attribute,
                    &language
                ) as? String {
                    result.append(localized)
                }
                return result
            }
        })
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw RepositoryError.invalidResponse
        }
    }

    private var indexCacheURL: URL {
        let encodedKey = Data(cacheKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SubtitleFonts", isDirectory: true)
            .appendingPathComponent("openlist-index-v2-\(encodedKey).json")
    }

    private var cacheKey: String {
        ([SubtitleFontManager.remoteServerURL] + SubtitleFontManager.remoteFontFolders.sorted())
            .joined(separator: "\n")
    }

    private func sourceConfiguration() throws -> Source {
        let input = SubtitleFontManager.remoteServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: input),
              let scheme = components.scheme,
              let host = components.host
        else { throw RepositoryError.invalidURL }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiPrefix = basePath.isEmpty ? "" : "/" + basePath
        components.path = apiPrefix + "/api/fs/get"
        components.query = nil
        components.fragment = nil
        guard let getAPIURL = components.url else { throw RepositoryError.invalidURL }

        components.path = apiPrefix + "/api/fs/list"
        guard let listAPIURL = components.url else { throw RepositoryError.invalidURL }

        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        guard origin.url != nil else { throw RepositoryError.invalidURL }

        return Source(
            serverURL: input.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            getAPIURL: getAPIURL,
            listAPIURL: listAPIURL
        )
    }

    private func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }

    private func joined(_ parent: String, _ name: String) -> String {
        let base = normalizedPath(parent)
        return base == "/" ? "/" + name : base + "/" + name
    }

    enum RepositoryError: LocalizedError {
        case invalidURL, invalidResponse, invalidFont, indexNotBuilt, noFoldersSelected, server(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: "字体源地址无效"
            case .invalidResponse: "字体服务器响应无效"
            case .invalidFont: "下载的文件不是有效字体"
            case .indexNotBuilt: "尚未建立字体索引"
            case .noFoldersSelected: "请先添加字体文件夹"
            case let .server(message): message
            }
        }
    }
}

private extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}
