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

    private static let importedFontNamesKey = "subtitleFontManager.importedFontNames"
    private static let supportedExtensions = Set(["ttf", "otf", "ttc", "otc"])

    static var importedFonts: [URL] {
        let names = UserDefaults.standard.stringArray(forKey: importedFontNamesKey) ?? []
        return names
            .map { fontsDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult
    static func install(from sourceURLs: [URL]) throws -> [URL] {
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

            let destinationURL = fontsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
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

    private static var installedFontNames: Set<String> {
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
                }
            }
        }
        return names
    }

    private static func normalizedFontName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static var fontsDirectory: URL {
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

private extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}
