//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import Foundation
import Logging

extension Logger {

    static func emby() -> Logger {
        Logger(label: "org.emby.iosplayer")
    }
}

enum AppLog {

    private static let logger = Logger.emby()

    /// Keeps the familiar NSLog formatting while routing application events
    /// through swift-log so Pulse and the debug console receive the same entry.
    static func event(
        _ format: String,
        _ arguments: CVarArg...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let message = String(format: format, arguments: arguments)
        let presentation = presentation(for: message)
        #if !DEBUG
        Foundation.NSLog("%@", presentation.text)
        #endif
        logger.info(
            "\(presentation.text)",
            metadata: [
                "channel": "application",
                "category": "\(presentation.category)",
                "event": "\(presentation.event)",
            ],
            source: "emby",
            file: file,
            function: function,
            line: line
        )
    }

    private static func presentation(for message: String) -> (text: String, category: String, event: String) {
        let parts = message.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let event = parts.first.map(String.init) ?? "Application"
        let details = parts.count > 1 ? String(parts[1]) : ""
        let category = category(for: event)
        let action = action(for: message, event: event)
        let readableDetails = localizedDetails(details)
        let suffix = readableDetails.isEmpty ? "" : "：\(readableDetails)"
        return ("[\(category)·\(action)]\(suffix)", category, event)
    }

    private static func category(for event: String) -> String {
        if event.contains("Subtitle") || event.contains("SubtitleFont") { return "字幕" }
        if event.contains("Audio") { return "音频" }
        if event.hasPrefix("EmbyPlayer") || event.hasPrefix("MPVPlayer") || event == "mpv:" { return "播放器" }
        if event.hasPrefix("EmbyHome") { return "首页" }
        if event.hasPrefix("EmbyNavigation") || event.hasPrefix("EmbyMainTab") { return "导航" }
        if event.hasPrefix("EmbySignIn") || event.hasPrefix("USER_SIGN_IN") { return "登录" }
        if event.hasPrefix("EmbyRoot") { return "应用启动" }
        if event.contains("PlaybackProgress") || event.contains("NowPlayable") { return "播放进度" }
        if event.contains("Smoke") || event.contains("SMOKE") { return "自动测试" }
        return "应用"
    }

    private static func action(for message: String, event: String) -> String {
        if message.contains("refresh-begin") { return "开始刷新" }
        if message.contains("refresh-apply") { return "刷新结果已应用" }
        if message.contains("refresh-step") || message.contains("refresh-library") { return "刷新步骤" }
        if message.contains("layout") { return "界面布局变化" }
        if event.contains("HomeContinueSplit") { return "整理继续观看" }
        if event.contains("Orientation") { return "屏幕方向切换" }
        if event.contains("Dismiss") { return "退出界面" }
        if event.contains("Teardown") { return "释放播放器资源" }
        if event.contains("DeferredStop") { return "停止播放" }
        if event.contains("Background") { return "前后台切换" }
        if event.contains("Buffering") { return "缓冲状态" }
        if event.contains("Subtitle") { return "字幕处理" }
        if event.contains("Audio") { return "音频处理" }
        if event.contains("Resume") { return "恢复播放" }
        if event.contains("Progress") { return "播放进度更新" }
        if event.contains("Navigation") { return "页面切换" }
        if event.contains("SignIn") { return "用户登录" }
        if event.contains("Root") { return "根界面切换" }
        if event.contains("FAIL") { return "测试失败" }
        if event.contains("PASS") { return "测试通过" }
        if event == "mpv:" { return "mpv诊断" }
        return "应用事件"
    }

    private static func localizedDetails(_ details: String) -> String {
        let replacements = [
            ("elapsed=", "耗时="),
            ("count=", "数量="),
            ("reason=", "原因="),
            ("result=", "结果="),
            ("error=", "错误="),
            ("title=", "标题="),
            ("item=", "媒体="),
            ("route=", "页面="),
            ("state=", "状态="),
            ("visible=", "是否显示="),
            ("language=", "语言="),
            ("index=", "序号="),
            ("startSeconds=", "起始秒数="),
        ]
        return replacements.reduce(details) { value, replacement in
            value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }
}

struct EmbyConsoleHandler: LogHandler {

    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set(newValue) {
            metadata[key] = newValue
        }
    }

    func log(
        event: LogEvent
    ) {
        let line = "[\(event.level.emoji) \(event.level.rawValue.capitalized)] \(event.file.shortFileName)#\(event.line):\(event.function) \(event.message)"
        let meta = (event.metadata ?? [:]).merging(self.metadata) { _, new in new }
        let metadataString = meta.map { "\t- \($0): \($1)" }.joined(separator: "\n")

        print(line)

        if metadataString.isNotEmpty {
            print(metadataString)
        }
    }
}

extension Logger.Level {
    var emoji: String {
        switch self {
        case .trace:
            "🟣"
        case .debug:
            "🔵"
        case .info:
            "🟢"
        case .notice:
            "🟠"
        case .warning:
            "🟡"
        case .error:
            "🔴"
        case .critical:
            "💥"
        }
    }
}
