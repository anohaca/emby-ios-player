//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct CompactLogoScrollView<Content: View>: ScrollContainerView {

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

        private var headerBottomColor: Color {
            [
                ImageType.backdrop,
                .thumb,
                .screenshot,
                .primary,
            ]
            .lazy
            .flatMap { imageType in
                [viewModel.item, viewModel.playButtonItem]
                    .compacted()
                    .compactMap { $0.blurHash(for: imageType)?.averageLinearColor }
            }
            .first ?? Color.secondarySystemFill
        }

        private var detailBackgroundColor: Color {
            headerBottomColor.mediaDetailBackgroundColor
        }

        private var headerImageSources: [ImageSource] {
            if let playButtonItem = viewModel.playButtonItem {
                viewModel.item.cinematicImageSources(maxWidth: 1320, quality: 90) + [
                    playButtonItem.imageSource(.primary, maxWidth: 1320, quality: 90),
                    playButtonItem.imageSource(.thumb, maxWidth: 1320, quality: 90),
                    playButtonItem.imageSource(.screenshot, maxWidth: 1320, quality: 90),
                    playButtonItem.imageSource(.backdrop, maxWidth: 1320, quality: 90),
                ]
            } else {
                viewModel.item.cinematicImageSources(maxWidth: 1320, quality: 90)
            }
        }

        @ViewBuilder
        private var headerView: some View {

            let bottomColor = detailBackgroundColor

            GeometryReader { proxy in
                ImageView(headerImageSources)
                    .aspectRatio(1.77, contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.70, alignment: .top)
                    .bottomEdgeGradient(bottomColor: bottomColor)
            }
        }

        var body: some View {
            OffsetScrollView(
                heightRatio: 0.5,
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
                VStack(alignment: .leading, spacing: 20) {
                    ItemView.OverviewView(item: viewModel.item)
                        .overviewLineLimit(4)
                        .taglineLineLimit(2)
                        .edgePadding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    content
                }
                .edgePadding(.vertical)
                .topEdgeGradient(
                    topColor: detailBackgroundColor,
                    bottomColor: detailBackgroundColor
                )
            }
        }
    }
}

extension ItemView.CompactLogoScrollView {

    struct OverlayView: View {

        @StoredValue(.User.itemViewAttributes)
        private var attributes

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        var body: some View {
            VStack(alignment: .center, spacing: 10) {
                ImageView(viewModel.item.imageURL(.logo, maxHeight: 70))
                    .placeholder { _ in
                        EmptyView()
                    }
                    .failure {
                        MaxHeightText(text: viewModel.item.displayTitle, maxHeight: 70)
                            .font(.largeTitle.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 70, alignment: .bottom)

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
                    ItemView.AttributesHStack(
                        attributes: attributes,
                        viewModel: viewModel
                    )

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
        }
    }
}
