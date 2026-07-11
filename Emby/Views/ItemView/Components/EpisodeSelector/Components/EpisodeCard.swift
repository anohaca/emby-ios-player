//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SeriesEpisodeSelector {

    final class EpisodePlaybackDisplayState: ObservableObject {

        static let `default` = EpisodePlaybackDisplayState()

        @Published
        private var revision = 0

        private var parentIsPlayed = false
        private var episodePlayedStates: [String: Bool] = [:]
        private var episodeProgressLabels: [String: String] = [:]
        private var episodePlayedPercentages: [String: Double] = [:]

        func update(parentIsPlayed: Bool, episodes: [BaseItemDto]) {
            let newEpisodePlayedStates = Dictionary(
                episodes.compactMap { episode -> (String, Bool)? in
                    guard let id = episode.id else { return nil }
                    return (id, episode.userData?.isPlayed == true)
                },
                uniquingKeysWith: { _, new in new }
            )
            let newEpisodeProgressLabels = Dictionary(
                episodes.compactMap { episode -> (String, String)? in
                    guard let id = episode.id,
                          let playbackPositionTicks = episode.userData?.playbackPositionTicks,
                          playbackPositionTicks > 0,
                          let progressLabel = Self.elapsedTimeLabel(ticks: playbackPositionTicks)
                    else { return nil }
                    return (id, progressLabel)
                },
                uniquingKeysWith: { _, new in new }
            )
            let newEpisodePlayedPercentages = Dictionary(
                episodes.compactMap { episode -> (String, Double)? in
                    guard let id = episode.id, let percentage = episode.userData?.playedPercentage else { return nil }
                    return (id, percentage)
                },
                uniquingKeysWith: { _, new in new }
            )

            guard self.parentIsPlayed != parentIsPlayed ||
                episodePlayedStates != newEpisodePlayedStates ||
                episodeProgressLabels != newEpisodeProgressLabels ||
                episodePlayedPercentages != newEpisodePlayedPercentages
            else { return }

            self.parentIsPlayed = parentIsPlayed
            self.episodePlayedStates = newEpisodePlayedStates
            self.episodeProgressLabels = newEpisodeProgressLabels
            self.episodePlayedPercentages = newEpisodePlayedPercentages
            revision += 1
        }

        func isPlayed(_ episode: BaseItemDto) -> Bool {
            if parentIsPlayed {
                return true
            }

            return episode.id.flatMap { episodePlayedStates[$0] } ?? episode.userData?.isPlayed == true
        }

        func progressLabel(_ episode: BaseItemDto) -> String? {
            if let label = episode.id.flatMap({ episodeProgressLabels[$0] }) {
                return label
            }
            guard let ticks = episode.userData?.playbackPositionTicks, ticks > 0 else { return nil }
            return Self.elapsedTimeLabel(ticks: ticks)
        }

        func playedPercentage(_ episode: BaseItemDto) -> Double {
            episode.id.flatMap { episodePlayedPercentages[$0] } ?? episode.userData?.playedPercentage ?? 0
        }

        private static func elapsedTimeLabel(ticks: Int) -> String? {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: Double(ticks) / 10_000_000)
        }
    }

    struct EpisodeCard: View {

        @Default(.accentColor)
        private var accentColor
        @Default(.Customization.Indicators.showPlayed)
        private var showPlayed

        @Namespace
        private var namespace

        @Router
        private var router

        @ObservedObject
        private var playbackDisplayState: EpisodePlaybackDisplayState

        let episode: BaseItemDto

        init(
            episode: BaseItemDto,
            playbackDisplayState: EpisodePlaybackDisplayState = .default
        ) {
            self.episode = episode
            self.playbackDisplayState = playbackDisplayState
        }

        private var isPlayedForDisplay: Bool {
            playbackDisplayState.isPlayed(episode)
        }

        private var progressLabelForDisplay: String? {
            isPlayedForDisplay ? nil : playbackDisplayState.progressLabel(episode)
        }

        @ViewBuilder
        private var overlayView: some View {
            if let progressLabel = progressLabelForDisplay {
                LandscapePosterProgressBar(
                    title: progressLabel,
                    progress: playbackDisplayState.playedPercentage(episode) / 100
                )
            } else if isPlayedForDisplay, showPlayed {
                WatchedIndicator(size: 25)
            }
        }

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        var body: some View {
            VStack(alignment: .leading) {
                Button {
                    router.route(
                        to: .videoPlayer(
                            item: episode,
                            queue: EpisodeMediaPlayerQueue(episode: episode)
                        )
                    )
                } label: {
                    Rectangle()
                        .fill(.complexSecondary)
                        .overlay {
                            ImageView(episode.imageSource(.primary, maxWidth: 250))
                                .image { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                                .failure {
                                    SystemImageContentView(systemName: episode.systemImage)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                        .overlay {
                            overlayView
                        }
                        .contentShape(.contextMenuPreview, Rectangle())
                        .backport
                        .matchedTransitionSource(id: "item", in: namespace)
                        .posterStyle(.landscape)
                        .posterShadow()
                }

                SeriesEpisodeSelector.EpisodeContent(
                    header: episode.displayTitle,
                    subHeader: episode.episodeLocator ?? .emptyDash,
                    content: episodeContent
                ) {
                    router.route(
                        to: .item(
                            item: episode,
                            shouldReturnHomeFromEpisodeBack: false
                        ),
                        in: namespace
                    )
                }
            }
        }
    }
}
