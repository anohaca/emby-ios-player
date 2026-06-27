//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import Foundation
import SwiftUI

extension HomeView {

    struct ContinueWatchingView: View {

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel

        @StateObject
        private var overlayState = BaseItemPosterOverlayState()

        // TODO: see how this looks across multiple screen sizes
        //       alongside PosterHStack + landscape
        // TODO: need better handling for iPadOS + portrait orientation
        private var columnCount: CGFloat {
            if UIDevice.isPhone {
                1.5
            } else {
                3.5
            }
        }

        private var overlaySignature: Int {
            var hasher = Hasher()

            for item in viewModel.resumeItems {
                hasher.combine(item.id)
                hasher.combine(item.userData?.playbackPositionTicks)
                hasher.combine(item.userData?.playedPercentage)
            }

            for item in viewModel.nextUpViewModel.elements {
                hasher.combine(item.id)
                hasher.combine(item.userData?.playbackPositionTicks)
                hasher.combine(item.userData?.playedPercentage)
            }

            for item in viewModel.nextEpisodeAfterPlayedItems {
                hasher.combine(item.id)
                hasher.combine(item.userData?.playbackPositionTicks)
                hasher.combine(item.userData?.playedPercentage)
                hasher.combine(item.userData?.isPlayed)
            }

            return hasher.finalize()
        }

        private var startedResumeItems: [BaseItemDto] {
            viewModel.resumeItems.filter(Self.hasPlaybackProgress)
        }

        private var unstartedResumeItems: [BaseItemDto] {
            viewModel.resumeItems.filter { !Self.hasPlaybackProgress($0) }
        }

        private var allUnstartedContinueItems: [BaseItemDto] {
            let startedIDs = Set(startedResumeItems.compactMap(\.id))
            let candidates = Array(viewModel.nextEpisodeAfterPlayedItems)

            let items = Self.uniqueItems(candidates).filter { item in
                guard let id = item.id else { return true }
                return !startedIDs.contains(id)
            }

            return items
        }

        private var unstartedContinueItems: [BaseItemDto] {
            Array(allUnstartedContinueItems.prefix(Self.unstartedItemLimit))
        }

        private static func hasPlaybackProgress(_ item: BaseItemDto) -> Bool {
            (item.userData?.playbackPositionTicks ?? 0) > 0 ||
                (item.startSeconds?.seconds ?? 0) > 0
        }

        private static func isUnplayedWithoutProgress(_ item: BaseItemDto) -> Bool {
            isPlayableVideo(item) &&
                item.userData?.isPlayed != true &&
                !hasPlaybackProgress(item)
        }

        private static func isPlayableVideo(_ item: BaseItemDto) -> Bool {
            item.type == .episode || item.type == .movie || item.type == .video
        }

        private static func uniqueItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
            var seen = Set<Int>()

            return items.filter { item in
                seen.insert(item.unwrappedIDHashOrZero).inserted
            }
        }

        private func play(_ item: BaseItemDto) {
            let queue: (any MediaPlayerQueue)? = {
                if item.type == .episode {
                    return EpisodeMediaPlayerQueue(episode: item)
                }
                return nil
            }()

            router.route(
                to: .videoPlayer(
                    item: item,
                    mediaSource: item.mediaSources?.first,
                    queue: queue
                )
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                resumeRow(items: startedResumeItems)

                if allUnstartedContinueItems.isNotEmpty {
                    unstartedHeader(items: allUnstartedContinueItems)

                    resumeRow(items: unstartedContinueItems)
                }
            }
            .onAppear {
                refreshOverlayState()
            }
            .onChange(of: overlaySignature) { _ in
                refreshOverlayState()
            }
        }

        @ViewBuilder
        private func unstartedHeader(items: [BaseItemDto]) -> some View {
            HStack {
                Text(L10n.unplayed)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])

                Spacer()

                SeeAllButton()
                    .onSelect {
                        let viewModel = PagingLibraryViewModel(
                            title: L10n.unplayed,
                            id: "home-unplayed-after-played",
                            items
                        )

                        router.route(to: .library(viewModel: viewModel))
                    }
            }
            .edgePadding(.horizontal)
        }

        @ViewBuilder
        private func resumeRow(items: [BaseItemDto]) -> some View {
            if items.isNotEmpty {
                CollectionHStack(
                    uniqueElements: items,
                    columns: columnCount
                ) { item in
                    PosterButton(
                        item: item,
                        type: .landscape,
                        posterAction: { _ in
                            play(item)
                        }
                    ) { namespace in
                        router.route(to: .item(item: item), in: namespace)
                    } label: {
                        if item.type == .episode {
                            PosterButton.EpisodeContentSubtitleContent(item: item)
                        } else {
                            PosterButton.TitleSubtitleContentView(item: item)
                        }
                    }
                }
                .clipsToBounds(false)
                .scrollBehavior(.continuousLeadingEdge)
                .contextMenu(for: BaseItemDto.self) { item in
                    Button {
                        viewModel.send(.setIsPlayed(true, item))
                    } label: {
                        Label(L10n.played, systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        viewModel.send(.setIsPlayed(false, item))
                    } label: {
                        Label(L10n.unplayed, systemImage: "minus.circle")
                    }
                }
                .posterOverlay(for: BaseItemDto.self) { item in
                    ContinueWatchingProgressOverlay(
                        item: item,
                        overlayState: overlayState
                    )
                }
                .frame(minHeight: stableMinimumHeight)
            }
        }

        private func refreshOverlayState() {
            let allUnstartedItems = allUnstartedContinueItems
            let unstartedItems = Array(allUnstartedItems.prefix(Self.unstartedItemLimit))
            overlayState.update(items: startedResumeItems + unstartedItems)

            #if DEBUG
            let nextUpItems = Array(viewModel.nextUpViewModel.elements)
            let nextUpUnstartedCount = nextUpItems.filter(Self.isUnplayedWithoutProgress).count
            let nextAfterPlayedCount = viewModel.nextEpisodeAfterPlayedItems.count
            let unstartedTitles = unstartedItems.prefix(6).map(Self.debugEpisodeTitle).joined(separator: " | ")

            NSLog(
                "EmbyHomeContinueSplit resume=%d started=%d unstartedResume=%d nextUp=%d nextUpUnstarted=%d nextAfterPlayed=%d finalUnstarted=%d allUnstarted=%d titles=%@",
                viewModel.resumeItems.count,
                startedResumeItems.count,
                unstartedResumeItems.count,
                nextUpItems.count,
                nextUpUnstartedCount,
                nextAfterPlayedCount,
                unstartedItems.count,
                allUnstartedItems.count,
                unstartedTitles
            )
            #endif
        }

        private var stableMinimumHeight: CGFloat {
            UIDevice.isPhone ? 184 : 220
        }

        private static let unstartedItemLimit = 20

        private static func debugEpisodeTitle(_ item: BaseItemDto) -> String {
            let series = item.seriesName ?? item.displayTitle
            let season = item.parentIndexNumber.map { "S\($0)" } ?? "S?"
            let episode = item.indexNumber.map { "E\($0)" } ?? "E?"
            return "\(series) \(season)\(episode)"
        }
    }
}

private struct ContinueWatchingProgressOverlay: View {

    let item: BaseItemDto

    @ObservedObject
    var overlayState: BaseItemPosterOverlayState

    private var value: BaseItemPosterOverlayState.Value {
        overlayState.value(for: item)
    }

    private var progressLabel: String {
        guard value.playbackPositionTicks > 0 else {
            return L10n.continue
        }

        let playbackSeconds = value.playbackPositionTicks / 10_000_000
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated

        return formatter.string(from: TimeInterval(playbackSeconds)) ?? L10n.continue
    }

    var body: some View {
        LandscapePosterProgressBar(
            title: progressLabel,
            progress: value.playedPercentage / 100
        )
    }
}
