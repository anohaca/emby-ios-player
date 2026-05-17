//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension ItemView {

    struct CinematicScrollView<Content: View>: ScrollContainerView {

        @Default(.Customization.CinematicItemViewType.usePrimaryImage)
        private var usePrimaryImage

        @Router
        private var router

        @ObservedObject
        private var viewModel: ItemViewModel

        private let content: Content

        init(
            viewModel: ItemViewModel,
            content: @escaping () -> Content
        ) {
            self.content = content()
            self.viewModel = viewModel
        }

        private var fallbackBottomColor: Color {
            let types: [ImageType] = if usePrimaryImage {
                [.primary]
            } else {
                [.backdrop, .thumb, .screenshot, .primary]
            }

            let items = [viewModel.item, viewModel.playButtonItem].compacted()

            return items
                .lazy
                .flatMap { item in
                    types.compactMap { item.blurHash(for: $0)?.averageLinearColor }
                }
                .first ?? Color.secondarySystemFill
        }

        private var detailBackgroundColor: Color {
            fallbackBottomColor.mediaDetailBackgroundColor
        }

        private func fallbackImageSources(maxWidth: CGFloat) -> [ImageSource] {
            let itemSources: [ImageSource] = if usePrimaryImage {
                [viewModel.item.imageSource(.primary, maxWidth: maxWidth, quality: 90)]
            } else {
                viewModel.item.cinematicImageSources(maxWidth: maxWidth, quality: 90)
            }

            guard let playButtonItem = viewModel.playButtonItem else {
                return itemSources
            }

            let playableFallbackSources: [ImageSource] = [
                playButtonItem.imageSource(.primary, maxWidth: maxWidth, quality: 90),
                playButtonItem.imageSource(.thumb, maxWidth: maxWidth, quality: 90),
                playButtonItem.imageSource(.screenshot, maxWidth: maxWidth, quality: 90),
                playButtonItem.imageSource(.backdrop, maxWidth: maxWidth, quality: 90),
            ]

            return itemSources + playableFallbackSources
        }

        @ViewBuilder
        private var headerView: some View {

            GeometryReader { proxy in
                if proxy.size.height.isZero { EmptyView() }
                else {
                    ImageView(fallbackImageSources(maxWidth: proxy.size.width))
                    .aspectRatio(usePrimaryImage ? (2 / 3) : 1.77, contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.6)
                    .bottomEdgeGradient(bottomColor: detailBackgroundColor)
                }
            }
        }

        var body: some View {
            OffsetScrollView(
                heightRatio: 0.75,
                backgroundColor: detailBackgroundColor
            ) {
                headerView
            } overlay: {
                OverlayView(viewModel: viewModel)
                    .edgePadding(.horizontal)
                    .edgePadding(.bottom)
                    .frame(maxWidth: .infinity)
                    .background {
                        detailBackgroundColor
                            .maskLinearGradient {
                                (location: 0, opacity: 0)
                                (location: 0.3, opacity: 1)
                                (location: 1, opacity: 1)
                            }
                    }
            } content: {
                content
                    .padding(.top, 10)
                    .edgePadding(.bottom)
                    .topEdgeGradient(
                        topColor: detailBackgroundColor,
                        bottomColor: detailBackgroundColor
                    )
            }
        }
    }
}

extension ItemView.CinematicScrollView {

    struct OverlayView: View {

        @Default(.Customization.CinematicItemViewType.usePrimaryImage)
        private var usePrimaryImage

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router
        @ObservedObject
        var viewModel: ItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .center, spacing: 10) {
                    if !usePrimaryImage {
                        ImageView(viewModel.item.imageURL(.logo, maxHeight: 100))
                            .placeholder { _ in
                                EmptyView()
                            }
                            .failure {
                                MaxHeightText(text: viewModel.item.displayTitle, maxHeight: 100)
                                    .font(.largeTitle.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                            }
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 100, alignment: .bottom)
                    }

                    DotHStack {
                        if let firstGenre = viewModel.item.genres?.first {
                            Text(firstGenre)
                        }

                        if let premiereYear = viewModel.item.premiereDateYear {
                            Text(premiereYear)
                        }

                        if let playButtonitem = viewModel.playButtonItem, let runtime = playButtonitem.runTimeLabel {
                            Text(runtime)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(Color(UIColor.lightGray))
                    .padding(.horizontal)

                    Group {
                        if viewModel.item.presentPlayButton {
                            ItemView.PlayButton(viewModel: viewModel)
                                .frame(height: 50)
                        }

                        ItemView.ActionButtonHStack(viewModel: viewModel)
                            .foregroundStyle(.white)
                            .frame(height: 50)
                    }
                    .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity)

                ItemView.OverviewView(item: viewModel.item)
                    .overviewLineLimit(3)
                    .taglineLineLimit(2)
                    .foregroundColor(.white)

                ItemView.AttributesHStack(
                    attributes: attributes,
                    viewModel: viewModel,
                    alignment: .leading
                )
            }
        }
    }
}
