//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: expose `ImageView.image` modifier for image aspect fill/fit

final class BaseItemPosterOverlayState: ObservableObject {

    struct Value: Equatable {
        let isFavorite: Bool
        let isPlayed: Bool
        let playbackPositionTicks: Int
        let playedPercentage: Double
        let unplayedItemCount: Int?

        init(userData: UserItemDataDto?) {
            isFavorite = userData?.isFavorite == true
            isPlayed = userData?.isPlayed == true
            playbackPositionTicks = userData?.playbackPositionTicks ?? 0
            playedPercentage = userData?.playedPercentage ?? 0
            unplayedItemCount = userData?.unplayedItemCount
        }
    }

    @Published
    private var revision = 0

    private var values: [String: Value] = [:]

    func update(items: [BaseItemDto]) {
        let newValues = Dictionary(
            items.compactMap { item -> (String, Value)? in
                guard let id = item.id else { return nil }
                return (id, Value(userData: item.userData))
            },
            uniquingKeysWith: { _, new in new }
        )

        guard values != newValues else { return }

        values = newValues
        revision += 1
    }

    func value(for item: BaseItemDto) -> Value {
        if let id = item.id, let value = values[id] {
            return value
        }

        return Value(userData: item.userData)
    }
}

struct PosterButton<Item: Poster>: View {

    @EnvironmentTypeValue<Item>(\.posterOverlayRegistry)
    private var posterOverlayRegistry

    @Namespace
    private var namespace

    @State
    private var posterSize: CGSize = .zero

    private let item: Item
    private let imageMaxWidth: CGFloat?
    private let usesContextMenuPreview: Bool
    private let type: PosterDisplayType
    private let label: any View
    private let action: (Namespace.ID) -> Void
    private let posterAction: ((Namespace.ID) -> Void)?

    private func labelView() -> some View {
        label
            .eraseToAnyView()
    }

    private func posterImageView(overlay: some View = EmptyView()) -> some View {
        PosterImage(item: item, type: type, maxWidth: imageMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { overlay }
            .contentShape(.contextMenuPreview, Rectangle())
            .posterCornerRadius(type)
            .backport
            .matchedTransitionSource(id: "item", in: namespace)
            .posterShadow()
    }

    private func posterView(overlay: some View = EmptyView()) -> some View {
        VStack(alignment: .leading) {
            posterImageView(overlay: overlay)

            labelView()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func trackContextMenuSize(_ content: some View) -> some View {
        if usesContextMenuPreview {
            content.trackingSize($posterSize)
        } else {
            content
        }
    }

    @ViewBuilder
    private func contextMenuView(_ content: some View) -> some View {
        if usesContextMenuPreview {
            let frameScale = 1.3

            content.matchedContextMenu(for: item) {
                posterView()
                    .frame(
                        width: posterSize.width * frameScale,
                        height: posterSize.height * frameScale
                    )
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: UIColor.secondarySystemGroupedBackground))
                    }
            }
        } else {
            content
        }
    }

    var body: some View {
        contextMenuView(Group {
            let overlay = posterOverlayRegistry?(item) ??
                PosterButton.DefaultOverlay(item: item)
                .eraseToAnyView()

            if let posterAction {
                VStack(alignment: .leading) {
                    Button {
                        posterAction(namespace)
                    } label: {
                        posterImageView(overlay: overlay)
                    }

                    Button {
                        action(namespace)
                    } label: {
                        labelView()
                    }
                }
                .modifier(TrackingContextMenuSizeModifier(isEnabled: usesContextMenuPreview, size: $posterSize))
            } else {
                Button {
                    action(namespace)
                } label: {
                    trackContextMenuSize(posterView(overlay: overlay))
                }
            }
        })
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.plain)
    }
}

extension PosterButton {

    init(
        item: Item,
        type: PosterDisplayType,
        imageMaxWidth: CGFloat? = nil,
        usesContextMenuPreview: Bool = true,
        posterAction: ((Namespace.ID) -> Void)? = nil,
        action: @escaping (Namespace.ID) -> Void,
        @ViewBuilder label: @escaping () -> any View
    ) {
        self.item = item
        self.imageMaxWidth = imageMaxWidth
        self.usesContextMenuPreview = usesContextMenuPreview
        self.type = type
        self.action = action
        self.posterAction = posterAction
        self.label = label()
    }
}

private struct TrackingContextMenuSizeModifier: ViewModifier {

    let isEnabled: Bool
    @Binding
    var size: CGSize

    func body(content: Content) -> some View {
        if isEnabled {
            content.trackingSize($size)
        } else {
            content
        }
    }
}

// TODO: remove these and replace with `TextStyle`

extension PosterButton {

    // MARK: Default Content

    struct TitleContentView: View {

        let title: String

        var body: some View {
            Text(title)
                .font(.footnote)
                .fontWeight(.regular)
                .foregroundStyle(.primary)
        }
    }

    struct SubtitleContentView: View {

        let subtitle: String?

        var body: some View {
            Text(subtitle ?? " ")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    struct TitleSubtitleContentView: View {

        let item: Item

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if item.showTitle {
                    TitleContentView(title: item.displayTitle)
                        .lineLimit(1, reservesSpace: true)
                }

                SubtitleContentView(subtitle: item.subtitle)
                    .lineLimit(1, reservesSpace: true)
            }
        }
    }

    // Content specific for BaseItemDto episode items
    struct EpisodeContentSubtitleContent: View {

        @Default(.Customization.Episodes.useSeriesLandscapeBackdrop)
        private var useSeriesLandscapeBackdrop

        let item: Item

        var body: some View {
            if let item = item as? BaseItemDto {
                // Unsure why this needs 0 spacing
                // compared to other default content
                VStack(alignment: .leading, spacing: 0) {
                    if item.showTitle, let seriesName = item.seriesName {
                        Text(seriesName)
                            .font(.footnote)
                            .fontWeight(.regular)
                            .foregroundColor(.primary)
                            .lineLimit(1, reservesSpace: true)
                    }

                    DotHStack(padding: 3) {
                        Text(item.seasonEpisodeLabel ?? .emptyDash)

                        if item.showTitle || useSeriesLandscapeBackdrop {
                            Text(item.displayTitle)
                        } else if let seriesName = item.seriesName {
                            Text(seriesName)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    struct BaseItemOverlay: View {

        @Default(.accentColor)
        private var accentColor
        @Default(.Customization.Indicators.showFavorited)
        private var showFavorited
        @Default(.Customization.Indicators.showProgress)
        private var showProgress
        @Default(.Customization.Indicators.showUnplayed)
        private var showUnplayed
        @Default(.Customization.Indicators.showPlayed)
        private var showPlayed

        @ObservedObject
        var displayState: BaseItemPosterOverlayState

        let item: BaseItemDto

        private var userData: BaseItemPosterOverlayState.Value {
            displayState.value(for: item)
        }

        var body: some View {
            ZStack {
                if item.canBePlayed, !item.isLiveStream, userData.isPlayed {
                    WatchedIndicator(size: 25)
                        .isVisible(showPlayed)
                } else {
                    if userData.playbackPositionTicks > 0 {
                        ProgressIndicator(progress: userData.playedPercentage / 100, height: 5)
                            .isVisible(showProgress)
                    } else if item.canBePlayed,
                              !item.isLiveStream,
                              showUnplayed != .none
                    {
                        UnwatchedIndicator(
                            size: 25,
                            count:
                            showUnplayed == .count ? userData.unplayedItemCount : nil
                        )
                        .foregroundStyle(accentColor.overlayColor, accentColor)
                    }
                }

                if userData.isFavorite {
                    FavoriteIndicator(size: 25)
                        .isVisible(showFavorited)
                }
            }
        }
    }

    // MARK: Default Overlay

    struct DefaultOverlay: View {

        @Default(.accentColor)
        private var accentColor
        @Default(.Customization.Indicators.showFavorited)
        private var showFavorited
        @Default(.Customization.Indicators.showProgress)
        private var showProgress
        @Default(.Customization.Indicators.showUnplayed)
        private var showUnplayed
        @Default(.Customization.Indicators.showPlayed)
        private var showPlayed

        let item: Item

        var body: some View {
            ZStack {
                if let item = item as? BaseItemDto {
                    if item.canBePlayed, !item.isLiveStream, item.userData?.isPlayed == true {
                        WatchedIndicator(size: 25)
                            .isVisible(showPlayed)
                    } else {
                        if (item.userData?.playbackPositionTicks ?? 0) > 0 {
                            ProgressIndicator(progress: (item.userData?.playedPercentage ?? 0) / 100, height: 5)
                                .isVisible(showProgress)
                        } else if item.canBePlayed,
                                  !item.isLiveStream,
                                  showUnplayed != .none
                        {
                            UnwatchedIndicator(
                                size: 25,
                                count:
                                showUnplayed == .count ? item.userData?.unplayedItemCount : nil
                            )
                            .foregroundStyle(accentColor.overlayColor, accentColor)
                        }
                    }

                    if item.userData?.isFavorite == true {
                        FavoriteIndicator(size: 25)
                            .isVisible(showFavorited)
                    }
                }
            }
        }
    }
}
