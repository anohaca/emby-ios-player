//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

// TODO: The content/loading/error states are implemented as different CollectionHStacks because it was just easy.
//       A theoretically better implementation would be a single CollectionHStack with cards that represent the state instead.
extension SeriesEpisodeSelector {

    struct EpisodeHStack: View {

        @ObservedObject
        var viewModel: SeasonItemViewModel

        @State
        private var didScrollToPlayButtonItem = false

        @StateObject
        private var proxy = CollectionHStackProxy()
        @StateObject
        private var playbackDisplayState = SeriesEpisodeSelector.EpisodePlaybackDisplayState()

        @State
        private var measuredWidth: CGFloat = 0
        @State
        private var playerTransitionLockedWidth: CGFloat?
        @State
        private var unlockPlayerTransitionTask: Task<Void, Never>?

        let playButtonItem: BaseItemDto?
        let inheritsPlayedState: Bool

        private func contentView(viewModel: SeasonItemViewModel) -> some View {
            CollectionHStack(
                uniqueElements: viewModel.elements,
                id: \.unwrappedIDHashOrZero,
                columns: UIDevice.isPhone ? 1.5 : 3.5
            ) { episode in
                SeriesEpisodeSelector.EpisodeCard(
                    episode: episode,
                    playbackDisplayState: playbackDisplayState
                )
            }
            .clipsToBounds(false)
            .scrollBehavior(.continuousLeadingEdge)
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .proxy(proxy)
            .onAppear {
                refreshPlaybackDisplayState()
            }
            .onChange(of: inheritsPlayedState) { _ in
                refreshPlaybackDisplayState()
            }
            .onChange(of: viewModel.elements) { _ in
                refreshPlaybackDisplayState()
            }
            .onChange(of: viewModel.userDataDisplayRevision) { _ in
                refreshPlaybackDisplayState()
            }
            .onFirstAppear {
                guard !didScrollToPlayButtonItem else { return }
                didScrollToPlayButtonItem = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let playButtonItem else { return }
                    guard let targetIndex = viewModel.elements.firstIndex(where: {
                        $0.unwrappedIDHashOrZero == playButtonItem.unwrappedIDHashOrZero
                    }) else { return }

                    // Avoid negative offsets on short seasons where the first card already belongs at the leading edge.
                    guard targetIndex > 0 else { return }

                    proxy.scrollTo(index: targetIndex, animated: false)
                }
            }
        }

        private func refreshPlaybackDisplayState() {
            playbackDisplayState.update(
                parentIsPlayed: inheritsPlayedState,
                episodes: Array(viewModel.elements)
            )
        }

        var body: some View {
            Group {
                switch viewModel.state {
                case .content:
                    if viewModel.elements.isEmpty {
                        EmptyHStack()
                    } else {
                        contentView(viewModel: viewModel)
                    }
                case let .error(error):
                    ErrorHStack(viewModel: viewModel, error: error)
                case .initial, .refreshing:
                    LoadingHStack()
                }
            }
            .frame(width: playerTransitionLockedWidth, alignment: .leading)
            .onSizeChanged { size, _ in
                guard playerTransitionLockedWidth == nil, size.width > 0 else { return }
                measuredWidth = size.width
            }
            .onReceive(Notifications[.willPresentVideoPlayer].publisher) {
                unlockPlayerTransitionTask?.cancel()
                unlockPlayerTransitionTask = nil
                guard measuredWidth > 0 else { return }
                playerTransitionLockedWidth = measuredWidth
            }
            .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
                unlockPlayerTransitionTask?.cancel()
                unlockPlayerTransitionTask = Task { @MainActor in
                    for _ in 0..<40 {
                        let screenSize = UIScreen.main.bounds.size
                        if screenSize.height >= screenSize.width {
                            try? await Task.sleep(for: .milliseconds(100))
                            guard !Task.isCancelled else { return }
                            playerTransitionLockedWidth = nil
                            unlockPlayerTransitionTask = nil
                            return
                        }

                        try? await Task.sleep(for: .milliseconds(25))
                        guard !Task.isCancelled else { return }
                    }
                }
            }
            .onDisappear {
                unlockPlayerTransitionTask?.cancel()
                unlockPlayerTransitionTask = nil
            }
        }
    }

    struct EmptyHStack: View {

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: UIDevice.isPhone ? 1.5 : 3.5
            ) { _ in
                SeriesEpisodeSelector.EmptyCard()
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }

    // TODO: better refresh design
    struct ErrorHStack: View {

        @ObservedObject
        var viewModel: SeasonItemViewModel

        let error: ErrorMessage

        var body: some View {
            CollectionHStack(
                count: 1,
                columns: UIDevice.isPhone ? 1.5 : 3.5
            ) { _ in
                SeriesEpisodeSelector.ErrorCard(error: error) {
                    viewModel.send(.refresh)
                }
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }

    struct LoadingHStack: View {

        var body: some View {
            CollectionHStack(
                count: Int.random(in: 2 ..< 5),
                columns: UIDevice.isPhone ? 1.5 : 3.5
            ) { _ in
                SeriesEpisodeSelector.LoadingCard()
            }
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(EdgeInsets.edgePadding / 2)
            .scrollDisabled(true)
        }
    }
}
