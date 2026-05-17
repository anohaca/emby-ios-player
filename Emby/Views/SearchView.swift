//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI
import UIKit
@_spi(Advanced) import SwiftUIIntrospect

// TODO: implement search view result type between `PosterHStack`
//       and `ListHStack` (3 row list columns)? (iOS only)
// TODO: have programs only pull recommended/current?
//       - have progress overlay
struct SearchView: View {

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters
    @Default(.Customization.searchPosterType)
    private var searchPosterType

    @FocusState
    private var isSearchFocused: Bool

    @Router
    private var router

    @State
    private var searchQuery = ""

    @TabItemSelected
    private var tabItemSelected

    @StateObject
    private var viewModel = SearchViewModel(filterViewModel: .init())

    @ViewBuilder
    private var suggestionsView: some View {
        VStack(spacing: 20) {
            ForEach(viewModel.suggestions) { item in
                Button(item.displayTitle) {
                    searchQuery = item.displayTitle
                }
            }
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if let movies = viewModel.items[.movie], movies.isNotEmpty {
                    itemsSection(
                        title: L10n.movies,
                        type: .movie,
                        items: movies,
                        posterType: searchPosterType
                    )
                }

                if let series = viewModel.items[.series], series.isNotEmpty {
                    itemsSection(
                        title: L10n.tvShows,
                        type: .series,
                        items: series,
                        posterType: searchPosterType
                    )
                }

                if let collections = viewModel.items[.boxSet], collections.isNotEmpty {
                    itemsSection(
                        title: L10n.collections,
                        type: .boxSet,
                        items: collections,
                        posterType: searchPosterType
                    )
                }

                if let episodes = viewModel.items[.episode], episodes.isNotEmpty {
                    itemsSection(
                        title: L10n.episodes,
                        type: .episode,
                        items: episodes,
                        posterType: searchPosterType
                    )
                }

                if let musicVideos = viewModel.items[.musicVideo], musicVideos.isNotEmpty {
                    itemsSection(
                        title: L10n.musicVideos,
                        type: .musicVideo,
                        items: musicVideos,
                        posterType: .landscape
                    )
                }

                if let videos = viewModel.items[.video], videos.isNotEmpty {
                    itemsSection(
                        title: L10n.videos,
                        type: .video,
                        items: videos,
                        posterType: .landscape
                    )
                }

                if let audio = viewModel.items[.audio], audio.isNotEmpty {
                    itemsSection(
                        title: L10n.audio,
                        type: .audio,
                        items: audio,
                        posterType: .square
                    )
                }

                if let musicAlbums = viewModel.items[.musicAlbum], musicAlbums.isNotEmpty {
                    itemsSection(
                        title: L10n.albums,
                        type: .musicAlbum,
                        items: musicAlbums,
                        posterType: .square
                    )
                }

                if let playlists = viewModel.items[.playlist], playlists.isNotEmpty {
                    itemsSection(
                        title: L10n.playlists,
                        type: .playlist,
                        items: playlists,
                        posterType: searchPosterType
                    )
                }

                if let programs = viewModel.items[.liveTvProgram], programs.isNotEmpty {
                    itemsSection(
                        title: L10n.programs,
                        type: .liveTvProgram,
                        items: programs,
                        posterType: .landscape
                    )
                }

                if let channels = viewModel.items[.tvChannel], channels.isNotEmpty {
                    itemsSection(
                        title: L10n.channels,
                        type: .tvChannel,
                        items: channels,
                        posterType: .square
                    )
                }

                if let musicArtists = viewModel.items[.musicArtist], musicArtists.isNotEmpty {
                    itemsSection(
                        title: L10n.artists,
                        type: .musicArtist,
                        items: musicArtists,
                        posterType: .portrait
                    )
                }

                if let people = viewModel.items[.person], people.isNotEmpty {
                    itemsSection(
                        title: L10n.people,
                        type: .person,
                        items: people,
                        posterType: .portrait
                    )
                }
            }
            .edgePadding(.vertical)
        }
    }

    private func select(_ item: BaseItemDto, in namespace: Namespace.ID) {
        switch item.type {
        case .program, .tvChannel:
            let provider = item.getPlaybackItemProvider(userSession: viewModel.userSession)
            router.route(to: .videoPlayer(provider: provider))
        default:
            router.route(to: .item(item: item), in: namespace)
        }
    }

    @ViewBuilder
    private func itemsSection(
        title: String,
        type: BaseItemKind?,
        items: [BaseItemDto],
        posterType: PosterDisplayType
    ) -> some View {
        PosterHStack(
            title: title,
            type: posterType,
            items: items,
            action: select
        )
        .trailing {
            SeeAllButton()
                .onSelect {
                    let routeType = type?.rawValue ?? "all"
                    let routeID = "search-\(routeType)-\(searchQuery.hashValue)-\(viewModel.filterViewModel.currentFilters.hashValue)"
                    let currentFilters = viewModel.filterViewModel.currentFilters
                    let viewModel = SearchLibraryViewModel(
                        title: title,
                        id: routeID,
                        query: searchQuery,
                        itemType: type,
                        filters: currentFilters.filtersForSearchText(searchQuery)
                    )
                    router.route(to: .library(viewModel: viewModel))
                }
        }
    }

    var body: some View {
        ZStack {
            EmbyAppBackgroundView()

            switch viewModel.state {
            case .error:
                viewModel.error.map {
                    ErrorView(error: $0)
                }
            case .initial:
                if viewModel.hasNoResults {
                    if viewModel.canSearch {
                        ContentUnavailableView.search
                    } else {
                        suggestionsView
                    }
                } else {
                    resultsView
                }
            case .searching:
                ProgressView()
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.items)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationTitle(L10n.search)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.search(query: searchQuery)
        }
        .navigationBarFilterDrawer(
            viewModel: viewModel.filterViewModel,
            types: enabledDrawerFilters
        )
        .onFirstAppear {
            viewModel.getSuggestions()
        }
        .onChange(of: searchQuery) { newValue in
            viewModel.search(query: newValue)
        }
        .onChange(of: isSearchFocused) { _ in
            SearchBarChrome.applyToActiveSearchBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            SearchBarChrome.applyIfActiveSearchField(notification.object)
        }
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.search
        )
        .introspect(
            .searchField,
            on: .iOS(.v16, .v17, .v18, .v26),
            scope: .ancestor
        ) { searchBar in
            SearchBarChrome.apply(to: searchBar)
        }
        .backport
        .searchFocused($isSearchFocused)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
    }
}

private enum SearchBarChrome {

    private static weak var activeSearchBar: UISearchBar?
    private static weak var activeTextField: UITextField?

    static func apply(to searchBar: UISearchBar) {
        activeSearchBar = searchBar
        activeTextField = searchBar.searchTextField
        applyAfterLayout(to: searchBar)

        DispatchQueue.main.async {
            applyAfterLayout(to: searchBar)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            applyAfterLayout(to: searchBar)
        }
    }

    static func applyToActiveSearchBar() {
        guard let activeSearchBar else { return }
        apply(to: activeSearchBar)
    }

    static func applyIfActiveSearchField(_ object: Any?) {
        guard
            let textField = object as? UITextField,
            textField === activeTextField
        else { return }

        applyToActiveSearchBar()
    }

    private static func applyAfterLayout(to searchBar: UISearchBar) {
        let textField = searchBar.searchTextField
        textField.backgroundColor = .clear
        textField.layer.backgroundColor = UIColor.clear.cgColor

        textField.subviews.forEach { subview in
            clearRectangularInputBackgrounds(in: subview, root: textField)
        }
    }

    private static func clearRectangularInputBackgrounds(in view: UIView, root: UIView) {
        let frame = view.convert(view.bounds, to: root)
        let preservesSystemFieldShape =
            abs(frame.minX) <= 2 &&
            abs(frame.minY) <= 2 &&
            abs(frame.width - root.bounds.width) <= 4 &&
            abs(frame.height - root.bounds.height) <= 4

        if !preservesSystemFieldShape {
            view.backgroundColor = .clear
            view.layer.backgroundColor = UIColor.clear.cgColor
        }

        view.subviews.forEach { subview in
            clearRectangularInputBackgrounds(in: subview, root: root)
        }
    }
}
