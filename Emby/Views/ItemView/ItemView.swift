//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct ItemView: View {

    protocol ScrollContainerView: View {

        associatedtype Content: View

        init(viewModel: ItemViewModel, content: @escaping () -> Content)
    }

    @Default(.Customization.itemViewType)
    private var itemViewType
    @Default(.VideoPlayer.Playback.defaultAudioLanguage)
    private var defaultAudioLanguage
    @Default(.VideoPlayer.Subtitle.defaultSubtitleLanguage)
    private var defaultSubtitleLanguage

    @Router
    private var router

    @StateObject
    private var viewModel: ItemViewModel

    @State
    private var viewportSize: CGSize = .zero
    @State
    private var isPlayerDismissTransitioning = false
    @State
    private var playerDismissTransitionTask: Task<Void, Never>?

    private let shouldReturnHomeFromEpisodeBack: Bool

    private static func typeViewModel(for item: BaseItemDto) -> ItemViewModel {
        switch item.type {
        case .boxSet, .person, .musicArtist:
            return CollectionItemViewModel(item: item)
        case .episode:
            return EpisodeItemViewModel(item: item)
        case .movie:
            return MovieItemViewModel(item: item)
        case .musicVideo, .video:
            return ItemViewModel(item: item)
        case .series:
            return SeriesItemViewModel(item: item)
        default:
            assertionFailure("Unsupported item")
            return ItemViewModel(item: item)
        }
    }

    init(
        item: BaseItemDto,
        shouldReturnHomeFromEpisodeBack: Bool = true
    ) {
        self._viewModel = StateObject(wrappedValue: Self.typeViewModel(for: item))
        self.shouldReturnHomeFromEpisodeBack = shouldReturnHomeFromEpisodeBack
    }

    @ViewBuilder
    private var scrollContentView: some View {
        switch viewModel.item.type {
        case .boxSet, .person, .musicArtist:
            CollectionItemContentView(viewModel: viewModel as! CollectionItemViewModel)
        case .episode, .musicVideo, .video:
            SimpleItemContentView(viewModel: viewModel)
        case .movie:
            MovieItemContentView(viewModel: viewModel as! MovieItemViewModel)
        case .series:
            SeriesItemContentView(viewModel: viewModel as! SeriesItemViewModel)
        default:
            Text(L10n.notImplementedYetWithType(viewModel.item.type ?? "--"))
        }
    }

    // TODO: break out into pad vs phone views based on item type
    private func scrollContainerView(
        viewModel: ItemViewModel,
        content: @escaping () -> some View
    ) -> any ScrollContainerView {

        if UIDevice.isPad {
            return iPadOSCinematicScrollView(viewModel: viewModel, content: content)
        }

        switch viewModel.item.type {
        case .movie, .series:
            switch itemViewType {
            case .compactPoster:
                return CompactPosterScrollView(viewModel: viewModel, content: content)
            case .compactLogo:
                return CompactLogoScrollView(viewModel: viewModel, content: content)
            case .cinematic:
                return CinematicScrollView(viewModel: viewModel, content: content)
            }
        case .person, .musicArtist:
            return CompactPosterScrollView(viewModel: viewModel, content: content)
        default:
            return SimpleScrollView(viewModel: viewModel, content: content)
        }
    }

    @ViewBuilder
    private var innerBody: some View {
        scrollContainerView(viewModel: viewModel) {
            scrollContentView
        }
        .eraseToAnyView()
    }

    private var shouldReturnHomeFromBack: Bool {
        shouldReturnHomeFromEpisodeBack && viewModel.item.type == .episode
    }

    private var transitionBackgroundColor: Color {
        let imageType: ImageType = switch viewModel.item.type {
        case .episode, .musicVideo, .video:
            .primary
        default:
            .backdrop
        }

        return (viewModel.item.blurHash(for: imageType)?.averageLinearColor ?? Color.secondarySystemFill)
            .mediaDetailBackgroundColor
    }

    private var isPortraitViewportStable: Bool {
        viewportSize.width > 0 &&
            viewportSize.height > 0 &&
            viewportSize.height >= viewportSize.width
    }

    var body: some View {
        ZStack {
            transitionBackgroundColor
                .ignoresSafeArea()

            switch viewModel.state {
            case .content:
                if !isPlayerDismissTransitioning {
                    innerBody
                        .navigationTitle(viewModel.item.displayTitle)
                }
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .onSizeChanged { size, _ in
            viewportSize = size
        }
        .background(transitionBackgroundColor.ignoresSafeArea())
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(shouldReturnHomeFromBack)
        .toolbar {
            if shouldReturnHomeFromBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.returnHome()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(L10n.home)
                }
            }
        }
        .refreshable {
            viewModel.send(.refresh)
        }
        .onFirstAppear {
            viewModel.send(.refresh)
        }
        .onChange(of: defaultAudioLanguage) { _ in
            viewModel.send(.applyDefaultTrackSelection)
        }
        .onChange(of: defaultSubtitleLanguage) { _ in
            viewModel.send(.applyDefaultTrackSelection)
        }
        .onReceive(Notifications[.willPresentVideoPlayer].publisher) {
            playerDismissTransitionTask?.cancel()
            playerDismissTransitionTask = nil
            isPlayerDismissTransitioning = false
        }
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            playerDismissTransitionTask?.cancel()
            isPlayerDismissTransitioning = true
            playerDismissTransitionTask = Task {
                await waitForStablePortraitViewport()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isPlayerDismissTransitioning = false
                }
            }
        }
        .onDisappear {
            playerDismissTransitionTask?.cancel()
            playerDismissTransitionTask = nil
        }
        .navigationBarMenuButton(
            isLoading: viewModel.backgroundStates.contains(.refresh),
            isHidden: !viewModel.item.showEditorMenu
        ) {
            ItemEditorMenu(item: viewModel.item)
        }
    }

    @MainActor
    private func waitForStablePortraitViewport() async {
        for _ in 0..<24 {
            if isPortraitViewportStable {
                try? await Task.sleep(for: .milliseconds(80))
                if isPortraitViewportStable {
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
