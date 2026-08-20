//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import CoreData
import Pulse
import PulseUI
import SwiftUI

struct GroupedLogView: View {

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case grouped = "分组"
        case original = "全部"

        var id: Self { self }
    }

    @StateObject private var viewModel = GroupedLogViewModel()
    @State private var displayMode = DisplayMode.grouped
    @State private var isShowingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("日志显示方式", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch displayMode {
            case .grouped:
                groupedList
            case .original:
                ConsoleView()
            }
        }
        .navigationTitle("日志")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("清空日志")
                .disabled(viewModel.isEmpty)
            }
        }
        .confirmationDialog(
            "确定清空全部日志？",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空日志", role: .destructive) {
                viewModel.removeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用事件、网络请求和相关日志内容都会被删除。")
        }
    }

    @ViewBuilder
    private var groupedList: some View {
        if viewModel.groups.isEmpty {
            ContentUnavailableView("暂无日志", systemImage: "text.page")
        } else {
            List(viewModel.groups) { group in
                DisclosureGroup {
                    ForEach(group.sections) { section in
                        DisclosureGroup {
                            ForEach(section.entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.time)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(entry.text)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 3)
                            }
                        } label: {
                            HStack {
                                Text(section.title)
                                Spacer(minLength: 8)
                                Text("\(section.entries.count) 条")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.title)
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            if group.entryCount > 1 {
                                Text("\(group.entryCount) 条")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(group.latestTime)
                            if group.duration > 0.001 {
                                Text("持续 \(group.duration.formatted(.number.precision(.fractionLength(2)))) 秒")
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.plain)
            .refreshable {
                viewModel.reload()
            }
        }
    }
}

@MainActor
private final class GroupedLogViewModel: ObservableObject {

    struct Entry: Identifiable {
        let id: NSManagedObjectID
        let date: Date
        let time: String
        let text: String
    }

    struct Group: Identifiable {
        let id: NSManagedObjectID
        let title: String
        let sections: [Section]

        var entries: [Entry] { sections.flatMap(\.entries).sorted { $0.date < $1.date } }
        var entryCount: Int { sections.reduce(0) { $0 + $1.entries.count } }
        var latestTime: String { entries.last?.time ?? "" }
        var duration: TimeInterval {
            guard let first = entries.first?.date, let last = entries.last?.date else { return 0 }
            return last.timeIntervalSince(first)
        }
    }

    struct Section: Identifiable {
        let id: NSManagedObjectID
        let key: String
        let title: String
        var entries: [Entry]
    }

    private struct Behavior {
        let key: String
        let title: String
        var alwaysStartsNewGroup = false
    }

    @Published private(set) var groups: [Group] = []
    var isEmpty: Bool { groups.isEmpty }

    private let store = LoggerStore.shared
    private var cancellable: AnyCancellable?
    private var reloadWorkItem: DispatchWorkItem?

    init() {
        reload()
        cancellable = store.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleReload()
            }
    }

    func reload() {
        reloadWorkItem?.cancel()
        let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchBatchSize = 1_000
        let windowSize = 1_000
        let maximumBoundaryLookback = 5_000
        request.fetchLimit = windowSize
        var messages = (try? store.viewContext.fetch(request)) ?? []

        // The oldest item in the visible window may be a continuation of a
        // behavior whose marker is just outside the window.  Fetch bounded
        // older pages until that marker is included, so grouping never falls
        // back to the synthetic startup behavior solely because of truncation.
        var fetchOffset = messages.count
        while let oldest = messages.last,
              Self.behavior(for: oldest) == nil,
              fetchOffset < windowSize + maximumBoundaryLookback
        {
            request.fetchOffset = fetchOffset
            request.fetchLimit = windowSize
            guard let olderPage = try? store.viewContext.fetch(request),
                  olderPage.isNotEmpty
            else { break }
            messages.append(contentsOf: olderPage)
            fetchOffset += olderPage.count
            if olderPage.count < windowSize { break }
        }

        groups = Self.makeGroups(from: messages)
    }

    func removeAll() {
        reloadWorkItem?.cancel()
        groups = []
        store.removeAll()
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private static func makeGroups(from newestFirstMessages: [LoggerMessageEntity]) -> [Group] {
        // Pulse persists a network message when the request finishes. Sorting only by the
        // message timestamp would therefore attach an older, in-flight request to whichever
        // page is visible at completion time. Use the task creation timestamp so network
        // entries stay with the behavior that initiated them.
        let messages = newestFirstMessages.enumerated().sorted { lhs, rhs in
            let lhsDate = effectiveDate(for: lhs.element)
            let rhsDate = effectiveDate(for: rhs.element)
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.offset > rhs.offset
        }.map(\.element)
        var result: [Group] = []
        var currentBehavior = Behavior(key: "startup", title: "应用启动准备")
        var currentEntries: [Entry] = []

        func appendCurrentGroup() {
            guard let first = currentEntries.first else { return }
            result.append(
                Group(
                    id: first.id,
                    title: currentBehavior.title,
                    sections: makeSections(from: currentEntries)
                )
            )
        }

        func appendToPreviousGroup(_ entry: Entry) {
            guard let previous = result.popLast() else {
                currentEntries.append(entry)
                return
            }
            result.append(
                Group(
                    id: previous.id,
                    title: previous.title,
                    sections: makeSections(from: previous.entries + [entry])
                )
            )
        }

        for message in messages {
            let entryDate = effectiveDate(for: message)
            let entry = Entry(
                id: message.objectID,
                date: entryDate,
                time: message.task?.formattedTimestamp ?? message.formattedTimestamp,
                text: displayText(for: message)
            )
            if let behavior = behavior(for: message),
               behavior.alwaysStartsNewGroup || behavior.key != currentBehavior.key
            {
                appendCurrentGroup()
                currentBehavior = behavior
                currentEntries = [entry]
            } else if currentBehavior.key == "page-log", isMediaImageRequest(message) {
                // The log screen has no remote media imagery of its own. SwiftUI/Nuke may
                // start a lazy image request from the outgoing page after the navigation
                // event, so creation time alone cannot identify that request's UI owner.
                // Keep it with the page group that was active before the log screen.
                appendToPreviousGroup(entry)
            } else {
                currentEntries.append(entry)
            }
        }
        appendCurrentGroup()
        return result.reversed()
    }

    private static func effectiveDate(for message: LoggerMessageEntity) -> Date {
        message.task?.createdAt ?? message.createdAt
    }

    private static func isMediaImageRequest(_ message: LoggerMessageEntity) -> Bool {
        message.task?.path?.lowercased().contains("/images/") == true
    }

    private static func makeSections(from entries: [Entry]) -> [Section] {
        var sections: [Section] = []
        var indexes: [String: Int] = [:]

        for entry in entries {
            let descriptor = descriptor(fromDisplayText: entry.text)
            if let index = indexes[descriptor.key] {
                sections[index].entries.append(entry)
            } else {
                indexes[descriptor.key] = sections.count
                sections.append(
                    Section(
                        id: entry.id,
                        key: descriptor.key,
                        title: descriptor.title,
                        entries: [entry]
                    )
                )
            }
        }
        return sections
    }

    private static func behavior(for message: LoggerMessageEntity) -> Behavior? {
        let text = message.text
        let event = message.metadata["event"] ?? message.label

        if event.hasPrefix("EmbyRoot") {
            return Behavior(key: "launch", title: "进入应用")
        }
        if event.hasPrefix("EmbySignIn") || event.hasPrefix("USER_SIGN_IN") {
            return Behavior(key: "sign-in", title: "登录账户")
        }
        if event.hasPrefix("EmbyHome"), text.contains("refresh-begin") || text.contains("开始刷新") {
            return Behavior(key: "home-refresh", title: "刷新首页", alwaysStartsNewGroup: true)
        }
        if event.hasPrefix("EmbyHome"), text.contains("home-onAppear") {
            return Behavior(key: "home", title: "进入首页")
        }
        if event.hasPrefix("EmbyMainTabSelection"),
           let tab = navigationValue(named: "tab", from: text)
        {
            return Behavior(
                key: "tab-\(tab)",
                title: "切换到\(pageTitle(for: tab))",
                alwaysStartsNewGroup: true
            )
        }
        if event.contains("PlayerWindow"), text.contains("present=success") {
            return Behavior(key: "playback", title: "播放视频")
        }
        if event.contains("PlayerResume") {
            return Behavior(key: "playback", title: "播放视频")
        }
        if event.contains("PlayerDismiss") {
            return Behavior(key: "exit-playback", title: "退出播放")
        }
        if event.contains("Background") && (text.contains("willResign") || text.contains("didEnter")) {
            return Behavior(key: "background", title: "进入后台")
        }
        if event.contains("Background") && (text.contains("willEnterForeground") || text.contains("didBecomeActive")) {
            return Behavior(key: "foreground", title: "返回前台")
        }
        if event.hasPrefix("EmbyNavigation"), text.contains("push") {
            guard let route = navigationValue(named: "route", from: text) else {
                return Behavior(key: "page-unknown", title: "进入未知页面")
            }
            if route == "videoPlayer" {
                return Behavior(key: "playback", title: "播放视频")
            }
            return Behavior(key: "page-\(route)", title: "进入\(pageTitle(for: route))")
        }
        if event.hasPrefix("EmbyNavigation"), text.contains("dismiss") {
            if text.contains("target=path") {
                let destination = navigationValue(named: "destination", from: text)
                    ?? (text.contains("remaining=0") ? "home" : nil)
                if let destination {
                    let key = destination == "home" ? "home" : "return-\(destination)"
                    return Behavior(key: key, title: "返回\(pageTitle(for: destination))")
                }
                return Behavior(key: "return-unknown", title: "返回上一页（目标未知）")
            }
            if text.contains("target=fullscreen") || text.contains("fullscreen-host") {
                return Behavior(key: "exit-playback", title: "退出播放")
            }
            return Behavior(key: "close-overlay", title: "关闭弹出页面")
        }
        return nil
    }

    private static func descriptor(fromDisplayText text: String) -> (key: String, title: String) {
        if text.contains("refresh-") ||
            text.contains("开始刷新") ||
            text.contains("刷新步骤") ||
            text.contains("刷新结果已应用")
        {
            return ("home-refresh", "首页刷新")
        }
        if text.contains("加载媒体图片") { return ("network-image", "图片加载") }
        if text.contains("传输媒体数据") { return ("network-media", "媒体传输") }
        if text.contains("网络") || text.contains("地址：") { return ("network", "网络请求") }
        guard text.first == "[", let end = text.firstIndex(of: "]") else {
            return ("application", "应用处理")
        }
        let heading = String(text[text.index(after: text.startIndex) ..< end])
        let parts = heading.split(separator: "·", maxSplits: 1).map(String.init)
        let category = parts.first ?? "应用"
        return ("application|\(category)", category)
    }

    private static func navigationValue(named name: String, from text: String) -> String? {
        let localizedName: String
        switch name {
        case "route": localizedName = "页面"
        case "tab": localizedName = "标签"
        default: localizedName = name
        }
        guard let range = text.range(of: "\(name)=") ?? text.range(of: "\(localizedName)=") else {
            return nil
        }
        let suffix = text[range.upperBound...]
        return suffix.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private static func pageTitle(for route: String) -> String {
        if route == "home" { return "首页" }
        if route.hasPrefix("item-") { return "媒体详情页" }
        if route.hasPrefix("library-") { return "影视库" }
        if route.hasPrefix("userSignIn-") { return "登录页" }

        switch route {
        case "home": return "首页"
        case "settings", "app-settings": return "设置"
        case "localUserSettings": return "用户设置"
        case "homeSectionSettings": return "首页类别设置"
        case "subtitleSettings": return "字幕设置"
        case "subtitleFontSettings": return "字幕字体设置"
        case "videoPlayerSettings": return "播放器设置"
        case "gestureSettings": return "手势设置"
        case "cacheStatistics": return "缓存统计"
        case "log": return "日志"
        case "favorites": return "收藏夹"
        case "search": return "搜索"
        case "media": return "媒体库"
        case "searchSubtitle": return "字幕搜索"
        case "mediaSourceInfo": return "媒体源信息"
        case "mediaStreamInfo": return "媒体流信息"
        case "itemImages", "itemImageDetails", "itemImageSelector": return "媒体图片"
        case "itemEditor", "editMetadata", "itemOverview": return "媒体编辑"
        case "castAndCrew": return "演职人员"
        case "filter", "itemFilterDrawerSelector": return "筛选设置"
        case "itemSortOptionSelector": return "排序设置"
        case "fontPicker": return "字体选择"
        case "serverConnection", "connectToServer": return "服务器连接"
        case "users": return "用户管理"
        case "downloadList": return "下载列表"
        case "videoPlayer": return "播放器"
        case "adminDashboard": return "服务器管理"
        case "debugSettings": return "调试设置"
        default: return "\(route) 页面"
        }
    }

    private static func descriptor(for message: LoggerMessageEntity) -> (key: String, title: String) {
        if let task = message.task {
            let method = task.httpMethod ?? "网络"
            let action = networkAction(method: method, path: task.path ?? "")
            return ("network|\(method)|\(action)", "网络 · \(action)")
        }

        let category = message.metadata["category"] ?? "应用"
        let event = message.metadata["event"] ?? message.label
        let action = actionTitle(from: message.text)
        return ("application|\(category)|\(event)", "\(category) · \(action)")
    }

    private static func actionTitle(from text: String) -> String {
        guard text.first == "[", let end = text.firstIndex(of: "]") else { return "应用事件" }
        let title = text[text.index(after: text.startIndex) ..< end]
        return title.split(separator: "·", maxSplits: 1).last.map(String.init) ?? String(title)
    }

    private static func displayText(for message: LoggerMessageEntity) -> String {
        guard let task = message.task else { return message.text }
        let method = task.httpMethod ?? ""
        let endpoint = [task.host, task.path].compactMap { $0 }.joined()
        let action = networkAction(method: method, path: task.path ?? "")
        let methodText = localizedMethod(method)
        let address = endpoint.isEmpty ? "" : "\n地址：\(endpoint)"
        return "\(methodText)：\(action)\(address)\n原始记录：\(message.text)"
    }

    private static func localizedMethod(_ method: String) -> String {
        switch method.uppercased() {
        case "GET": "读取"
        case "POST": "提交"
        case "PUT": "更新"
        case "DELETE": "删除"
        case "PATCH": "修改"
        default: method.isEmpty ? "网络请求" : method
        }
    }

    private static func networkAction(method: String, path: String) -> String {
        let normalized = path.lowercased()

        if normalized.contains("/playing/progress") { return "上报播放进度" }
        if normalized.contains("/playing/stopped") { return "上报停止播放" }
        if normalized.contains("/playing") { return "上报开始播放" }
        if normalized.contains("/resume") { return "获取继续播放列表" }
        if normalized.contains("/nextup") { return "获取下一集" }
        if normalized.contains("/shows/") && normalized.contains("/episodes") { return "获取剧集列表" }
        if normalized.contains("/seasons") { return "获取季度列表" }
        if normalized.contains("/latest") { return "获取最近新增" }
        if normalized.contains("/search") || normalized.contains("searchterm") { return "搜索媒体" }
        if normalized.contains("/images/") { return "加载媒体图片" }
        if normalized.contains("/playbackinfo") { return "获取播放信息" }
        if normalized.contains("/subtitles/") { return "加载字幕" }
        if normalized.contains("/items/") && normalized.contains("/userdata") { return "更新观看状态" }
        if normalized.contains("/items") { return "获取媒体列表" }
        if normalized.contains("/users") { return "获取用户信息" }
        if normalized.contains("/system/info") { return "获取服务器信息" }
        if normalized.contains("/sessions") { return "同步播放会话" }
        if normalized.contains("/fonts") { return "加载字幕字体" }
        if normalized.contains("/videos/") || normalized.contains("/audio/") { return "传输媒体数据" }

        return "\(localizedMethod(method))网络数据"
    }
}
