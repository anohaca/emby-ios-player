//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct CacheStatisticsView: View {

    @State
    private var snapshot = CacheStatisticsSnapshot.empty

    @State
    private var isLoading = false

    var body: some View {
        Form {
            Section {
                LabeledContent("总占用", value: snapshot.totalSizeText)

                Button {
                    refresh()
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("重新统计")
                    }
                }
                .disabled(isLoading)
            } footer: {
                Text("统计只读取当前应用沙盒内的缓存和本地数据，不会清理任何文件。")
            }

            cacheSection("图片缓存", rows: snapshot.imageRows)
            cacheSection("页面缓存", rows: snapshot.pageRows)
            cacheSection("本地数据", rows: snapshot.localRows)

            Section {
                LabeledContent("mpv 缓存", value: snapshot.mpvCacheEnabled ? "开启" : "关闭")
                LabeledContent("前向缓存上限", value: "\(snapshot.mpvForwardCacheMiB) MiB")
                LabeledContent("后向缓存上限", value: "\(snapshot.mpvBackCacheMiB) MiB")
                LabeledContent("预读时间", value: "\(snapshot.mpvReadaheadSeconds) 秒")
            } header: {
                Text("播放缓存")
            } footer: {
                Text("mpv 播放缓存是播放时的内存缓存，关闭播放器后不保留到磁盘，所以这里显示配置而不是文件大小。")
            }
        }
        .navigationTitle("缓存统计")
        .task {
            if snapshot == .empty {
                refresh()
            }
        }
    }

    @ViewBuilder
    private func cacheSection(_ title: String, rows: [CacheStatisticsRow]) -> some View {
        Section {
            ForEach(rows) { row in
                LabeledContent(row.title, value: row.sizeText)
            }
        } header: {
            Text(title)
        }
    }

    private func refresh() {
        guard !isLoading else { return }

        isLoading = true

        Task {
            let snapshot = await CacheStatisticsCollector.snapshot()
            await MainActor.run {
                self.snapshot = snapshot
                self.isLoading = false
            }
        }
    }
}

private struct CacheStatisticsSnapshot: Equatable {

    static let empty = CacheStatisticsSnapshot(
        imageRows: [],
        pageRows: [],
        localRows: [],
        mpvCacheEnabled: Defaults[.VideoPlayer.Playback.mpvCacheEnabled],
        mpvForwardCacheMiB: Defaults[.VideoPlayer.Playback.mpvDemuxerMaxBytesMiB],
        mpvBackCacheMiB: Defaults[.VideoPlayer.Playback.mpvDemuxerMaxBackBytesMiB],
        mpvReadaheadSeconds: Defaults[.VideoPlayer.Playback.mpvDemuxerReadaheadSeconds]
    )

    let imageRows: [CacheStatisticsRow]
    let pageRows: [CacheStatisticsRow]
    let localRows: [CacheStatisticsRow]
    let mpvCacheEnabled: Bool
    let mpvForwardCacheMiB: Int
    let mpvBackCacheMiB: Int
    let mpvReadaheadSeconds: Int

    var totalSizeText: String {
        let total = (imageRows + pageRows + localRows).reduce(0) { $0 + $1.size }
        return ByteCountFormatter.cacheString(fromByteCount: total)
    }
}

private struct CacheStatisticsRow: Identifiable, Equatable {

    let id: String
    let title: String
    let size: Int64

    var sizeText: String {
        ByteCountFormatter.cacheString(fromByteCount: size)
    }
}

private enum CacheStatisticsCollector {

    static func snapshot() async -> CacheStatisticsSnapshot {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default

            let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

            let imageRows = [
                CacheStatisticsRow(
                    id: "poster-cache",
                    title: "海报/头图磁盘缓存",
                    size: imageCacheSize(in: cachesDirectory, fileManager: fileManager)
                ),
                CacheStatisticsRow(
                    id: "local-image-cache",
                    title: "离线图片缓存",
                    size: documentsDirectory
                        .map {
                            directorySize(
                                $0.appendingPathComponent("Caches/org.emby.iosplayer.local", isDirectory: true),
                                fileManager: fileManager
                            )
                        } ?? 0
                ),
            ]

            let pageRows = [
                CacheStatisticsRow(
                    id: "home-cache",
                    title: "首页缓存",
                    size: cachesDirectory
                        .map {
                            directorySize(
                                $0.appendingPathComponent("HomeViewModelCache", isDirectory: true),
                                fileManager: fileManager
                            )
                        } ?? 0
                ),
            ]

            let localRows = [
                CacheStatisticsRow(
                    id: "downloads",
                    title: "离线下载",
                    size: directorySize(.downloadsDirectory, fileManager: fileManager)
                ),
                CacheStatisticsRow(
                    id: "database",
                    title: "本地数据库",
                    size: databaseSize(
                        searchRoots: [applicationSupportDirectory, documentsDirectory, cachesDirectory].compactMap(\.self),
                        fileManager: fileManager
                    )
                ),
                CacheStatisticsRow(
                    id: "temporary",
                    title: "临时文件",
                    size: directorySize(.temporaryDirectory, fileManager: fileManager)
                ),
            ]

            return CacheStatisticsSnapshot(
                imageRows: imageRows,
                pageRows: pageRows,
                localRows: localRows,
                mpvCacheEnabled: Defaults[.VideoPlayer.Playback.mpvCacheEnabled],
                mpvForwardCacheMiB: Defaults[.VideoPlayer.Playback.mpvDemuxerMaxBytesMiB],
                mpvBackCacheMiB: Defaults[.VideoPlayer.Playback.mpvDemuxerMaxBackBytesMiB],
                mpvReadaheadSeconds: Defaults[.VideoPlayer.Playback.mpvDemuxerReadaheadSeconds]
            )
        }.value
    }

    private static func imageCacheSize(in cachesDirectory: URL?, fileManager: FileManager) -> Int64 {
        guard let cachesDirectory else { return 0 }
        let candidates = descendants(
            of: cachesDirectory,
            fileManager: fileManager
        ).filter { url in
            let path = url.path.lowercased()
            return path.contains("nuke") ||
                path.contains("org.emby.iosplayer") ||
                path.contains("posters")
        }

        let exactSize = candidates.reduce(Int64(0)) { $0 + fileSize($1, fileManager: fileManager) }
        if exactSize > 0 {
            return exactSize
        }

        return directorySize(cachesDirectory, fileManager: fileManager)
    }

    private static func databaseSize(searchRoots: [URL], fileManager: FileManager) -> Int64 {
        searchRoots.reduce(Int64(0)) { partialResult, root in
            partialResult + descendants(of: root, fileManager: fileManager).reduce(Int64(0)) { total, url in
                let name = url.lastPathComponent
                guard name == "Emby.sqlite" ||
                    name == "Emby.sqlite-wal" ||
                    name == "Emby.sqlite-shm" else {
                    return total
                }

                return total + fileSize(url, fileManager: fileManager)
            }
        }
    }

    private static func descendants(of root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }
    }

    private static func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return descendants(of: url, fileManager: fileManager).reduce(Int64(0)) {
            $0 + fileSize($1, fileManager: fileManager)
        }
    }

    private static func fileSize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey]),
              values.isDirectory != true else {
            return 0
        }

        return Int64(values.totalFileAllocatedSize ?? 0)
    }
}

private extension ByteCountFormatter {

    static func cacheString(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(byteCount, 0))
    }
}
