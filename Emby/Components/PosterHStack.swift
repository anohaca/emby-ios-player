//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

private struct HomeTransitionLockedRowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var homeTransitionLockedRowWidth: CGFloat? {
        get { self[HomeTransitionLockedRowWidthKey.self] }
        set { self[HomeTransitionLockedRowWidthKey.self] = newValue }
    }
}

// TODO: Migrate to single `header: View`

struct PosterHStack<Element: Poster, Data: Collection>: View where Data.Element == Element, Data.Index == Int {

    private var data: Data
    private var header: () -> any View
    private var title: String?
    private var type: PosterDisplayType
    private var label: (Element) -> any View
    private var trailingContent: () -> any View
    private var action: (Element, Namespace.ID) -> Void
    private var posterAction: ((Element, Namespace.ID) -> Void)?

    @StateObject
    private var baseItemOverlayState = BaseItemPosterOverlayState()
    @Environment(\.homeTransitionLockedRowWidth)
    private var homeTransitionLockedRowWidth

    private var baseItems: [BaseItemDto] {
        data.compactMap { $0 as? BaseItemDto }
    }

    private var baseItemOverlaySignature: Int {
        var hasher = Hasher()

        for item in baseItems {
            hasher.combine(item.id)
            hasher.combine(item.userData?.isFavorite)
            hasher.combine(item.userData?.isPlayed)
            hasher.combine(item.userData?.playbackPositionTicks)
            hasher.combine(item.userData?.playedPercentage)
            hasher.combine(item.userData?.unplayedItemCount)
        }

        return hasher.finalize()
    }

    @ViewBuilder
    private var stack: some View {
        GeometryReader { proxy in
            let width = max(homeTransitionLockedRowWidth ?? proxy.size.width, 320)

            CollectionHStack(
                uniqueElements: data,
                layout: layout
            ) { item in
                PosterButton(
                    item: item,
                    type: type,
                    posterAction: posterAction.map { posterAction in
                        { namespace in
                            posterAction(item, namespace)
                        }
                    }
                ) { namespace in
                    action(item, namespace)
                } label: {
                    label(item).eraseToAnyView()
                }
            }
            .clipsToBounds(false)
            .dataPrefix(20)
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(itemSpacing)
            .scrollBehavior(.continuousLeadingEdge)
            .frame(width: width, height: rowHeight(for: width), alignment: .leading)
        }
        .posterOverlay(for: BaseItemDto.self) { item in
            PosterButton<BaseItemDto>.BaseItemOverlay(
                displayState: baseItemOverlayState,
                item: item
            )
        }
        .frame(height: rowHeight(for: homeTransitionLockedRowWidth ?? 430))
        .onAppear {
            refreshBaseItemOverlayState()
        }
        .onChange(of: baseItemOverlaySignature) { _ in
            refreshBaseItemOverlayState()
        }
    }

    private func refreshBaseItemOverlayState() {
        baseItemOverlayState.update(items: baseItems)
    }

    private var layout: CollectionHStackLayout {
        if UIDevice.isPhone {
            .grid(
                columns: type == .landscape ? 2 : 3,
                rows: 1,
                columnTrailingInset: 0
            )
        } else {
            .minimumWidth(
                columnWidth: type == .landscape ? 220 : 140,
                rows: 1
            )
        }
    }

    private func itemWidth(for width: CGFloat) -> CGFloat {
        if UIDevice.isPhone {
            let columns: CGFloat = type == .landscape ? 2 : 3
            let safeWidth = max(width, 320)
            let horizontalInsets = EdgeInsets.edgePadding * 2
            return (safeWidth - horizontalInsets - itemSpacing * (columns - 1)) / columns
        }

        return type == .landscape ? 220 : 140
    }

    private func rowHeight(for width: CGFloat) -> CGFloat {
        let imageHeight: CGFloat

        switch type {
        case .landscape:
            imageHeight = itemWidth(for: width) / 1.77
        case .portrait:
            imageHeight = itemWidth(for: width) * 1.5
        case .square:
            imageHeight = itemWidth(for: width)
        }

        return imageHeight + 40
    }

    private var itemSpacing: CGFloat {
        EdgeInsets.edgePadding / 2
    }

    private var stableMinimumHeight: CGFloat {
        rowHeight(for: 430)
    }

    var body: some View {
        VStack(alignment: .leading) {

            HStack {
                header()
                    .eraseToAnyView()

                Spacer()

                trailingContent()
                    .eraseToAnyView()
            }
            .edgePadding(.horizontal)

            stack
        }
    }
}

extension PosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        posterAction: ((Element, Namespace.ID) -> Void)? = nil,
        action: @escaping (Element, Namespace.ID) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { PosterButton<Element>.TitleSubtitleContentView(item: $0) }
    ) {
        self.init(
            data: items,
            header: { DefaultHeader(title: title) },
            title: title,
            type: type,
            label: label,
            trailingContent: { EmptyView() },
            action: action,
            posterAction: posterAction
        )
    }

    func trailing(@ViewBuilder _ content: @escaping () -> any View) -> Self {
        copy(modifying: \.trailingContent, with: content)
    }
}

// MARK: Default Header

extension PosterHStack {

    struct DefaultHeader: View {

        let title: String?

        var body: some View {
            if let title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
            }
        }
    }
}
