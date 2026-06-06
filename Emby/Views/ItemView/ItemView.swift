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
    private var collectionLayoutRevision = 0
    @State
    private var playerDismissLayoutTask: Task<Void, Never>?
    @State
    private var viewportSize: CGSize = .zero
    @State
    private var isLeavingItemView = false

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

    var body: some View {
        ZStack {
            transitionBackgroundColor
                .ignoresSafeArea()

            switch viewModel.state {
            case .content:
                innerBody
                    .navigationTitle(viewModel.item.displayTitle)
            case let .error(error):
                ErrorView(error: error)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .background(CollectionLayoutInvalidator(revision: collectionLayoutRevision))
        .background(ItemViewLifecycleObserver(isLeaving: $isLeavingItemView))
        .allowsHitTesting(!isLeavingItemView)
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
            playerDismissLayoutTask?.cancel()
            playerDismissLayoutTask = nil
        }
        .onReceive(Notifications[.willDismissVideoPlayer].publisher) {
            playerDismissLayoutTask?.cancel()
            playerDismissLayoutTask = Task {
                await rebuildContentAfterStablePortraitLayout()
            }
        }
        .onDisappear {
            playerDismissLayoutTask?.cancel()
            playerDismissLayoutTask = nil
        }
        .navigationBarMenuButton(
            isLoading: viewModel.backgroundStates.contains(.refresh),
            isHidden: !viewModel.item.showEditorMenu
        ) {
            ItemEditorMenu(item: viewModel.item)
        }
    }

    @MainActor
    private func rebuildContentAfterStablePortraitLayout() async {
        for _ in 0..<40 {
            if viewportSize.width > 0, viewportSize.height >= viewportSize.width {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }

                if viewportSize.height >= viewportSize.width {
                    collectionLayoutRevision += 1
                    playerDismissLayoutTask = nil
                    return
                }
            }

            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
        }
    }

}

private struct CollectionLayoutInvalidator: UIViewRepresentable {

    let revision: Int

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision

        DispatchQueue.main.async {
            guard let rootView = view.window?.rootViewController?.view else { return }
            invalidateCollectionLayouts(in: rootView)
            rootView.setNeedsLayout()
            rootView.layoutIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var revision = 0
    }

    private func invalidateCollectionLayouts(in view: UIView) {
        if let collectionView = view as? UICollectionView {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.setNeedsLayout()
        }

        for subview in view.subviews {
            invalidateCollectionLayouts(in: subview)
        }
    }
}

private struct ItemViewLifecycleObserver: UIViewControllerRepresentable {

    @Binding
    var isLeaving: Bool

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController(isLeaving: $isLeaving)
    }

    func updateUIViewController(_ controller: ObserverViewController, context: Context) {
        controller.isLeaving = $isLeaving
    }

    final class ObserverViewController: UIViewController {

        var isLeaving: Binding<Bool>

        init(isLeaving: Binding<Bool>) {
            self.isLeaving = isLeaving
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isLeaving.wrappedValue = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isLeaving.wrappedValue = true
        }
    }
}
