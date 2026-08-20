//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import OrderedCollections
import SwiftUI

// TODO: Show show name in episode subheader

extension ItemView {

    struct CollectionItemContentView: View {

        typealias Element = OrderedDictionary<BaseItemKind, ItemLibraryViewModel>.Elements.Element

        @Router
        private var router

        @ObservedObject
        var viewModel: CollectionItemViewModel

        private var sortedSections: [Element] {
            guard viewModel.item.type == .boxSet else {
                return Array(viewModel.sections.elements)
            }

            let sections = Array(viewModel.sections.elements)
            return sections.enumerated()
                .sorted { lhs, rhs in
                    let lhsPriority = videoSectionPriority(lhs.element.key)
                    let rhsPriority = videoSectionPriority(rhs.element.key)

                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    } else {
                        return lhs.offset < rhs.offset
                    }
                }
                .map(\.element)
        }

        private func videoSectionPriority(_ kind: BaseItemKind) -> Int {
            switch kind {
            case .video:
                0
            case .musicVideo:
                1
            case .movie:
                2
            default:
                3
            }
        }

        private func shouldPlayPosterImage(in kind: BaseItemKind) -> Bool {
            guard viewModel.item.type == .boxSet else { return false }

            switch kind {
            case .video, .musicVideo, .movie:
                return true
            default:
                return false
            }
        }

        private func play(_ item: BaseItemDto) {
            guard item.isPlayable else {
                router.route(to: .item(item: item))
                return
            }

            let queue: (any MediaPlayerQueue)? =
                CollectionMediaPlayerQueue.make(
                    items: viewModel.playableItems,
                    currentItem: item
                ) ?? (item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil)

            router.route(
                to: .videoPlayer(
                    item: item,
                    mediaSource: item.mediaSources?.first,
                    queue: queue
                )
            )
        }

        private func episodeHStack(element: Element) -> some View {
            VStack(alignment: .leading) {

                Text(L10n.episodes)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibility(addTraits: [.isHeader])
                    .edgePadding(.horizontal)

                CollectionHStack(
                    uniqueElements: element.value.elements,
                    id: \.unwrappedIDHashOrZero,
                    columns: UIDevice.isPhone ? 1.5 : 3.5
                ) { episode in
                    SeriesEpisodeSelector.EpisodeCard(episode: episode)
                }
                .scrollBehavior(.continuousLeadingEdge)
                .insets(horizontal: EdgeInsets.edgePadding)
                .itemSpacing(EdgeInsets.edgePadding / 2)
            }
        }

        private func posterHStack(element: Element) -> some View {
            PosterHStack(
                title: element.key.pluralDisplayTitle,
                type: element.key.preferredPosterDisplayType,
                items: element.value.elements,
                posterAction: shouldPlayPosterImage(in: element.key) ? { item, _ in
                    play(item)
                } : nil
            ) { item, namespace in
                router.route(to: .item(item: item), in: namespace)
            }
            .trailing {
                SeeAllButton()
                    .onSelect {
                        router.route(to: .library(viewModel: element.value))
                    }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Items

                ForEach(
                    sortedSections,
                    id: \.key
                ) { element in
                    if element.key == .episode {
                        episodeHStack(element: element)
                    } else {
                        posterHStack(element: element)
                    }
                }

                // MARK: Genres

                if let genres = viewModel.item.itemGenres, genres.isNotEmpty {
                    ItemView.GenresHStack(genres: genres)
                }

                // MARK: Studios

                if let studios = viewModel.item.studios, studios.isNotEmpty {
                    ItemView.StudiosHStack(studios: studios)
                }

                // MARK: Similar

                if viewModel.similarItems.isNotEmpty {
                    ItemView.SimilarItemsHStack(items: viewModel.similarItems)
                }

                ItemView.AboutView(viewModel: viewModel)
            }
        }
    }
}
