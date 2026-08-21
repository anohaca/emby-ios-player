import Foundation
import SwiftUI

private struct AniRSSResponse<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

private struct AniRSSSchedule: Decodable {
    let weekList: [AniRSSWeek]
}

private struct AniRSSWeek: Codable, Equatable, Identifiable {
    let weekLabel: String
    let items: [AniRSSItem]

    var id: String { weekLabel }
}

private struct AniRSSItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let releaseDate: String?
    let cover: String?
    let image: String?
    let subgroup: String?
    let currentEpisodeNumber: Int?
    let totalEpisodeNumber: Int?
    let score: Double?
    let enable: Bool?
    let tmdb: AniRSSTMDB?
    let tmdbId: String?

    var tmdbID: String? { tmdbId ?? tmdb?.id }

    var episodeText: String {
        "\(currentEpisodeNumber ?? 0) / \(totalEpisodeNumber.map(String.init) ?? "*")"
    }
}

private struct AniRSSTMDB: Codable, Equatable {
    let id: String?
}

private struct AutoBangumiSchedule: Decodable {
    let items: [AutoBangumiEntry]
}

private struct AutoBangumiEntry: Decodable {
    let rule: AutoBangumiRule
    let metadata: AutoBangumiMetadata
}

private struct AutoBangumiRule: Decodable {
    let id: Int
    let officialTitle: String?
    let titleRaw: String?
    let ruleName: String?
    let season: Int?
    let groupName: String?
    let posterLink: String?
    let deleted: Bool?
    let epsCollect: Bool?
}

private struct AutoBangumiMetadata: Decodable {
    let tmdbId: String?
    let bgmName: String?
    let title: String?
    let jpTitle: String?
    let releaseDate: String?
    let weekLabel: String?
    let image: String?
    let score: Double?
    let currentEpisodeNumber: Int?
    let totalEpisodeNumber: Int?
    let notFound: Bool?
}

private enum AniRSSScheduleError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "ANI-RSS 返回了无法识别的数据"
        case let .server(message):
            message
        }
    }
}

@MainActor
private final class WeeklyScheduleViewModel: ViewModel {
    struct PlaybackIndicator: Codable, Equatable {
        let isPlayed: Bool
        let unplayedCount: Int?
    }

    enum State {
        case initial
        case loading
        case content
        case failed(String)
    }

    @Published private(set) var weeks: [AniRSSWeek] = []
    @Published private(set) var playbackIndicators: [String: PlaybackIndicator] = [:]
    @Published private(set) var matchedLibraryItems: [String: BaseItemDto] = [:]
    @Published private(set) var state: State = .initial
    private static let calendarLabels = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private let baseURL: URL
    private let autoBangumiURL: URL
    private var didStartLoading = false

    init(baseURL: URL) {
        self.baseURL = baseURL
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.port = 7892
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        self.autoBangumiURL = components?.url ?? baseURL
        super.init()
    }

    private var cacheSuffix: String {
        Data(baseURL.absoluteString.utf8).base64EncodedString()
    }

    private var cacheKey: String { "weeklySchedule.cache.v2.\(cacheSuffix)" }
    private var indicatorCacheKey: String { "weeklySchedule.indicators.v2.\(cacheSuffix)" }

    func load() async {
        guard !didStartLoading else { return }
        didStartLoading = true
        restoreCache()
        restoreIndicatorCache()
        await requestSchedule()
    }

    func reload() async {
        await requestSchedule()
    }

    private func requestSchedule() async {
        let hasCachedContent = !weeks.isEmpty
        if !hasCachedContent {
            state = .loading
        }

        do {
            async let nativeResult = Self.fetchNativeSchedule(baseURL: baseURL)
            async let autoBangumiResult = Self.fetchAutoBangumiSchedule(baseURL: autoBangumiURL)
            let (native, autoBangumi) = await (nativeResult, autoBangumiResult)

            guard native != nil || autoBangumi != nil else {
                throw AniRSSScheduleError.server("ANI-RSS 和 AutoBangumi 均无法连接")
            }

            let latestWeeks = Self.sortedFromToday(Self.merge(
                native: native,
                autoBangumi: autoBangumi,
                autoBangumiURL: autoBangumiURL
            ))
            if latestWeeks != weeks {
                weeks = latestWeeks
                saveCache(latestWeeks)
            }
            await loadPlaybackIndicators()
            state = .content
        } catch {
            state = hasCachedContent ? .content : .failed(error.localizedDescription)
        }
    }

    private func restoreCache() {
        guard let data = UserDefaults.currentUserSuite.data(forKey: cacheKey),
              let cachedWeeks = try? JSONDecoder().decode([AniRSSWeek].self, from: data),
              !cachedWeeks.isEmpty
        else { return }
        weeks = Self.sortedFromToday(cachedWeeks)
        state = .content
    }

    private func saveCache(_ weeks: [AniRSSWeek]) {
        guard let data = try? JSONEncoder().encode(weeks) else { return }
        UserDefaults.currentUserSuite.set(data, forKey: cacheKey)
    }

    private static func sortedFromToday(_ weeks: [AniRSSWeek]) -> [AniRSSWeek] {
        let todayIndex = max(0, min(calendarLabels.count - 1, Calendar.current.component(.weekday, from: Date()) - 1))
        let labels = Array(calendarLabels[todayIndex...]) + Array(calendarLabels[..<todayIndex])
        let positions = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        return weeks.sorted {
            positions[$0.weekLabel, default: Int.max] < positions[$1.weekLabel, default: Int.max]
        }
    }

    private func loadPlaybackIndicators() async {
        do {
            var parameters = EmbyPortItemsParameters()
            parameters.includeItemTypes = [.series]
            parameters.isRecursive = true
            parameters.limit = 10_000
            parameters.fields = [.providerIDs]
            let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
                parameters,
                as: EmbyPortItemsResponse<BaseItemDto>.self
            )
            let series = response.items ?? []
            let seriesByTMDB = Dictionary(
                series.compactMap { item -> (String, BaseItemDto)? in
                    guard let tmdbID = Self.tmdbID(of: item) else { return nil }
                    return (tmdbID, item)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let seriesByTitle = Dictionary(
                series.map { (Self.normalized($0.displayTitle), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var result: [String: PlaybackIndicator] = [:]
            var matches: [String: BaseItemDto] = [:]
            for scheduleItem in weeks.flatMap(\.items) {
                let match = scheduleItem.tmdbID.flatMap { seriesByTMDB[$0] } ??
                    seriesByTitle[Self.normalized(scheduleItem.title)]
                guard let match else { continue }
                matches[scheduleItem.id] = match
                result[scheduleItem.id] = PlaybackIndicator(
                    isPlayed: match.userData?.isPlayed == true,
                    unplayedCount: match.userData?.unplayedItemCount
                )
            }
            let oldMatchIDs = matchedLibraryItems.mapValues(\.id)
            let newMatchIDs = matches.mapValues(\.id)
            if oldMatchIDs != newMatchIDs {
                matchedLibraryItems = matches
            }
            if playbackIndicators != result {
                playbackIndicators = result
                saveIndicatorCache(result)
            }
        } catch {
            // Keep the last known indicators when the Emby server is temporarily unavailable.
        }
    }

    private func restoreIndicatorCache() {
        guard let data = UserDefaults.currentUserSuite.data(forKey: indicatorCacheKey),
              let indicators = try? JSONDecoder().decode([String: PlaybackIndicator].self, from: data)
        else { return }
        playbackIndicators = indicators
    }

    private func saveIndicatorCache(_ indicators: [String: PlaybackIndicator]) {
        guard let data = try? JSONEncoder().encode(indicators) else { return }
        UserDefaults.currentUserSuite.set(data, forKey: indicatorCacheKey)
    }

    private static func fetchNativeSchedule(baseURL: URL) async -> AniRSSSchedule? {
        do {
            var request = URLRequest(url: baseURL.appending(path: "api/listAni"))
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else { return nil }
            let envelope = try JSONDecoder().decode(AniRSSResponse<AniRSSSchedule>.self, from: data)
            return (200 ..< 300).contains(envelope.code) ? envelope.data : nil
        } catch {
            return nil
        }
    }

    private static func fetchAutoBangumiSchedule(baseURL: URL) async -> AutoBangumiSchedule? {
        do {
            var request = URLRequest(url: baseURL.appending(path: "api/v1/integration/ani-rss"))
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else { return nil }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AutoBangumiSchedule.self, from: data)
        } catch {
            return nil
        }
    }

    private static func merge(
        native: AniRSSSchedule?,
        autoBangumi: AutoBangumiSchedule?,
        autoBangumiURL: URL
    ) -> [AniRSSWeek] {
        var grouped = Dictionary(uniqueKeysWithValues: (native?.weekList ?? []).map { ($0.weekLabel, $0.items) })

        for entry in autoBangumi?.items ?? [] {
            let metadata = entry.metadata
            let rule = entry.rule
            if metadata.notFound == true || metadata.weekLabel?.isEmpty != false { continue }

            let current = metadata.currentEpisodeNumber ?? 0
            let total = metadata.totalEpisodeNumber ?? 0
            let completed = current > 0 && total > 0 && current >= total
            let allNative = grouped.values.flatMap { $0 }
            let match = allNative.first { sameTitle($0, rule: rule, metadata: metadata) }

            if completed {
                for key in grouped.keys {
                    grouped[key]?.removeAll { sameTitle($0, rule: rule, metadata: metadata) }
                }
                continue
            }

            if let match {
                for key in grouped.keys {
                    guard let index = grouped[key]?.firstIndex(where: { $0.id == match.id }) else { continue }
                    let original = grouped[key]![index]
                    grouped[key]![index] = AniRSSItem(
                        id: original.id, title: original.title, releaseDate: original.releaseDate,
                        cover: original.cover, image: original.image, subgroup: original.subgroup,
                        currentEpisodeNumber: max(original.currentEpisodeNumber ?? 0, current),
                        totalEpisodeNumber: max(original.totalEpisodeNumber ?? 0, total),
                        score: original.score ?? metadata.score, enable: original.enable,
                        tmdb: original.tmdb, tmdbId: original.tmdbId ?? metadata.tmdbId
                    )
                }
                continue
            }

            let title = firstNonempty(rule.officialTitle, metadata.title, rule.titleRaw, rule.ruleName) ?? "未命名番剧"
            let item = AniRSSItem(
                id: "autobangumi-\(rule.id)", title: title,
                releaseDate: metadata.releaseDate.map { String($0.prefix(10)) }, cover: nil,
                image: posterURL([metadata.image, rule.posterLink], relativeTo: autoBangumiURL)?.absoluteString,
                subgroup: rule.groupName,
                currentEpisodeNumber: metadata.currentEpisodeNumber,
                totalEpisodeNumber: metadata.totalEpisodeNumber, score: metadata.score,
                enable: !(rule.deleted ?? false), tmdb: nil, tmdbId: metadata.tmdbId
            )
            grouped[metadata.weekLabel!, default: []].append(item)
        }

        return grouped.map { AniRSSWeek(weekLabel: $0.key, items: $0.value) }
    }

    private static func sameTitle(_ item: AniRSSItem, rule: AutoBangumiRule, metadata: AutoBangumiMetadata) -> Bool {
        let left = normalized(item.title)
        let candidates = [rule.officialTitle, rule.titleRaw, rule.ruleName, metadata.title, metadata.jpTitle, metadata.bgmName]
        return !left.isEmpty && candidates.compactMap { $0 }.map(normalized).contains(left)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func tmdbID(of item: BaseItemDto) -> String? {
        item.providerIDs?.first {
            $0.key.caseInsensitiveCompare("tmdb") == .orderedSame
        }?.value
    }

    private static func firstNonempty(_ values: String?...) -> String? {
        values.compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }.first
    }

    private static func posterURL(_ values: [String?], relativeTo baseURL: URL) -> URL? {
        guard let value = values.compactMap({ $0 }).first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

struct WeeklyScheduleView: View {
    @StateObject private var viewModel: WeeklyScheduleViewModel
    @Router private var router
    @Environment(\.homePageDragSuppressed) private var isHomePageDragSuppressed
    private let baseURL: URL
    private let topContentInset: CGFloat
    private let onScrollOffsetChange: ((CGFloat) -> Void)?

    init(
        baseURL: URL,
        topContentInset: CGFloat = 0,
        onScrollOffsetChange: ((CGFloat) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.topContentInset = topContentInset
        self.onScrollOffsetChange = onScrollOffsetChange
        self._viewModel = StateObject(wrappedValue: WeeklyScheduleViewModel(baseURL: baseURL))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        contentStateView
            .task {
                await viewModel.load()
            }
    }

    @ViewBuilder
    private var contentStateView: some View {
        switch viewModel.state {
        case .initial, .loading:
            ProgressView("正在读取 ANI-RSS…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("无法加载星期表")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.reload() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .content:
            scheduleContent
        }
    }

    @ViewBuilder
    private var scheduleContent: some View {
        if viewModel.weeks.allSatisfy(\.items.isEmpty) {
            ScrollView {
                VStack(spacing: 24) {
                    if topContentInset > 0 {
                        Color.clear.frame(height: topContentInset)
                    }

                    ContentUnavailableView("没有星期数据", systemImage: "calendar")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
                .frame(maxWidth: .infinity)
            }
            .clearScrollViewBackground()
            .onScrollViewOffsetChange { offset in
                onScrollOffsetChange?(offset)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if topContentInset > 0 {
                        Color.clear.frame(height: topContentInset)
                    }

                    ForEach(viewModel.weeks) { week in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(week.weekLabel)
                                    .font(.headline)
                                Text("\(week.items.count) 部")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            if week.items.isEmpty {
                                Text("暂无订阅")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                            } else {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                    ForEach(week.items) { item in
                                        WeeklyScheduleCard(
                                            item: item,
                                            baseURL: baseURL,
                                            playbackIndicator: viewModel.playbackIndicators[item.id]
                                        ) { namespace in
                                            select(item, in: namespace)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .clearScrollViewBackground()
            .refreshable {
                await viewModel.reload()
            }
            .onScrollViewOffsetChange { offset in
                onScrollOffsetChange?(offset)
            }
        }
    }

    private func select(_ item: AniRSSItem, in namespace: Namespace.ID) {
        guard !isHomePageDragSuppressed else { return }

        if let libraryItem = viewModel.matchedLibraryItems[item.id] {
            router.route(to: .item(item: libraryItem), in: namespace)
        } else {
            let searchViewModel = SearchLibraryViewModel(
                title: item.title,
                id: "weekly-\(item.id)",
                query: item.title,
                itemType: .series,
                filters: nil
            )
            router.route(to: .library(viewModel: searchViewModel))
        }
    }

}

private struct WeeklyScheduleCard: View {
    @Namespace private var namespace

    let item: AniRSSItem
    let baseURL: URL
    let playbackIndicator: WeeklyScheduleViewModel.PlaybackIndicator?
    let action: (Namespace.ID) -> Void

    var body: some View {
        Button {
            action(namespace)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                poster
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .posterStyle(.portrait)
                    .overlay {
                        if playbackIndicator?.isPlayed == true {
                            WatchedIndicator(size: 25)
                        } else if let count = playbackIndicator?.unplayedCount, count > 0 {
                            UnwatchedIndicator(size: 25, count: count)
                                .foregroundStyle(Color.accentColor.overlayColor, Color.accentColor)
                        }
                    }
                    .backport
                    .matchedTransitionSource(id: "item", in: namespace)

                Text(item.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(height: 17, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if item.enable == false {
                Text("未启用")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(5)
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        ZStack {
            posterPlaceholder

            if let url = posterURL {
                ImageView(url)
                    .image { image in
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .placeholder { _ in
                        posterPlaceholder
                    }
                    .failure {
                        posterPlaceholder
                    }
            }
        }
        // Do not use an infinite height inside LazyVGrid. It makes each card
        // expand to the scroll view's proposed height and causes rows to overlap.
        .aspectRatio(2 / 3, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "film.stack")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var posterURL: URL? {
        if let cover = item.cover, !cover.isEmpty {
            var components = URLComponents(
                url: baseURL.appending(path: "api/file"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "filename", value: Data(cover.utf8).base64EncodedString()),
            ]
            return components?.url
        }

        if let image = item.image, !image.isEmpty {
            return URL(string: image)
        }

        return nil
    }
}
