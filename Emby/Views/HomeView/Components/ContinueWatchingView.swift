//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
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

            return hasher.finalize()
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
            CollectionHStack(
                uniqueElements: viewModel.resumeItems,
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
            .onAppear {
                refreshOverlayState()
            }
            .onChange(of: overlaySignature) { _ in
                refreshOverlayState()
            }
            .frame(minHeight: viewModel.resumeItems.isEmpty ? nil : stableMinimumHeight)
        }

        private func refreshOverlayState() {
            overlayState.update(items: Array(viewModel.resumeItems))
        }

        private var stableMinimumHeight: CGFloat {
            UIDevice.isPhone ? 184 : 220
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
