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
    }

    @ViewBuilder
    private var groupedList: some View {
        if viewModel.groups.isEmpty {
            ContentUnavailableView("暂无日志", systemImage: "text.page")
        } else {
            List(viewModel.groups) { group in
                DisclosureGroup {
                    ForEach(group.entries) { entry in
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
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.title)
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            if group.entries.count > 1 {
                                Text("\(group.entries.count) 条")
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
        let entries: [Entry]

        var latestTime: String { entries.last?.time ?? "" }
        var duration: TimeInterval {
            guard let first = entries.first?.date, let last = entries.last?.date else { return 0 }
            return last.timeIntervalSince(first)
        }
    }

    @Published private(set) var groups: [Group] = []

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
        let messages = (try? store.messages(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
            predicate: nil
        )) ?? []
        groups = Self.makeGroups(from: Array(messages.prefix(1_000)))
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private static func makeGroups(from newestFirstMessages: [LoggerMessageEntity]) -> [Group] {
        let messages = newestFirstMessages.reversed()
        var result: [Group] = []
        var currentKey: String?
        var currentTitle = ""
        var currentEntries: [Entry] = []

        func appendCurrentGroup() {
            guard let first = currentEntries.first else { return }
            result.append(Group(id: first.id, title: currentTitle, entries: currentEntries))
        }

        for message in messages {
            let descriptor = descriptor(for: message)
            let entry = Entry(
                id: message.objectID,
                date: message.createdAt,
                time: message.formattedTimestamp,
                text: displayText(for: message)
            )
            let isAdjacent = currentEntries.last.map {
                message.createdAt.timeIntervalSince($0.date) <= 1
            } ?? false

            if currentKey == descriptor.key, isAdjacent {
                currentEntries.append(entry)
            } else {
                appendCurrentGroup()
                currentKey = descriptor.key
                currentTitle = descriptor.title
                currentEntries = [entry]
            }
        }
        appendCurrentGroup()
        return result.reversed()
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
