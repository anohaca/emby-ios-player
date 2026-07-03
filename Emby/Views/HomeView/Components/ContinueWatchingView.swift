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

        enum Kind {
            case resume
            case continueWatching
        }

        @Router
        private var router

        @ObservedObject
        var viewModel: HomeViewModel

        let kind: Kind

        @StateObject
        private var overlayState = BaseItemPosterOverlayState()
        @Environment(\.homeTransitionLockedRowWidth)
        private var homeTransitionLockedRowWidth

        // TODO: see how this looks across multiple screen sizes
        //       alongside PosterHStack + landscape
        // TODO: need better handling for iPadOS + portrait orientation
        private var columnCount: CGFloat {
            if UIDevice.isPhone {
                1.6
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
                switch kind {
                case .resume:
                    if startedResumeItems.isNotEmpty {
                        resumeRow(items: startedResumeItems)
                    }

                case .continueWatching:
                    if allUnstartedContinueItems.isNotEmpty {
                        unstartedHeader(items: allUnstartedContinueItems)

                        resumeRow(items: unstartedContinueItems)
                    }
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
                Text(L10n.continueWatching)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])

                Spacer()

                SeeAllButton()
                    .onSelect {
                        let viewModel = PagingLibraryViewModel(
                            title: L10n.continueWatching,
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
                GeometryReader { proxy in
                    let width = max(homeTransitionLockedRowWidth ?? proxy.size.width, 320)

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
                    .frame(width: width, height: rowHeight(for: width), alignment: .leading)
                }
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
                .frame(height: rowHeight(for: homeTransitionLockedRowWidth ?? 430))
            }
        }

        private func refreshOverlayState() {
            let visibleItems: [BaseItemDto]

            switch kind {
            case .resume:
                visibleItems = startedResumeItems
            case .continueWatching:
                visibleItems = unstartedContinueItems
            }

            overlayState.update(items: visibleItems)

            #if DEBUG
            let nextUpItems = Array(viewModel.nextUpViewModel.elements)
            let nextUpUnstartedCount = nextUpItems.filter(Self.isUnplayedWithoutProgress).count
            let nextAfterPlayedCount = viewModel.nextEpisodeAfterPlayedItems.count
            let unstartedTitles = unstartedContinueItems.prefix(6).map(Self.debugEpisodeTitle).joined(separator: " | ")

            NSLog(
                "EmbyHomeContinueSplit kind=%@ resume=%d started=%d unstartedResume=%d nextUp=%d nextUpUnstarted=%d nextAfterPlayed=%d finalUnstarted=%d allUnstarted=%d titles=%@",
                String(describing: kind),
                viewModel.resumeItems.count,
                startedResumeItems.count,
                unstartedResumeItems.count,
                nextUpItems.count,
                nextUpUnstartedCount,
                nextAfterPlayedCount,
                unstartedContinueItems.count,
                allUnstartedContinueItems.count,
                unstartedTitles
            )
            #endif
        }

        private func rowHeight(for width: CGFloat) -> CGFloat {
            let imageHeight = itemWidth(for: width) * 9 / 16
            let labelHeight: CGFloat = 76
            return max(UIDevice.isPhone ? 230 : 260, imageHeight + labelHeight)
        }

        private func itemWidth(for width: CGFloat) -> CGFloat {
            let safeWidth = max(width, 320)
            let horizontalInsets = EdgeInsets.edgePadding * 2
            let visibleGapCount = max(ceil(columnCount) - 1, 0)
            return (safeWidth - horizontalInsets - itemSpacing * visibleGapCount) / columnCount
        }

        private var itemSpacing: CGFloat {
            EdgeInsets.edgePadding
        }

        private var stableMinimumHeight: CGFloat {
            rowHeight(for: 430)
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
