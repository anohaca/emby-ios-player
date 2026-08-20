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

// TODO: implement search view result type between `PosterHStack`
//       and `ListHStack` (3 row list columns)? (iOS only)
// TODO: have programs only pull recommended/current?
//       - have progress overlay
struct SearchView: View {

    @Default(.Customization.Search.enabledDrawerFilters)
    private var enabledDrawerFilters
    @Default(.Customization.Home.hiddenSectionIDs)
    private var hiddenHomeSectionIDs
    @Default(.Customization.searchPosterType)
    private var searchPosterType

    @State
    private var isSearchFocused = false

    @Router
    private var router

    @State
    private var searchQuery = ""

    @TabItemSelected
    private var tabItemSelected

    @StateObject
    private var viewModel = SearchViewModel(filterViewModel: .init())

    @ViewBuilder
    private var searchHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)

                ClearSearchTextField(
                    text: $searchQuery,
                    placeholder: L10n.search,
                    isFocused: $isSearchFocused
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
            .padding(.horizontal, 22)

            if enabledDrawerFilters.isNotEmpty {
                NavigationBarFilterDrawer(
                    viewModel: viewModel.filterViewModel,
                    types: enabledDrawerFilters
                )
            }
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var suggestionsView: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 20
            ) {
                ForEach(viewModel.suggestions) { item in
                    Button {
                        searchQuery = item.displayTitle
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PosterImage(
                                item: item,
                                type: .portrait,
                                maxWidth: 180
                            )
                            .posterCornerRadius(.portrait)

                            Text(item.displayTitle)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            searchHeader
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            viewModel.search(query: searchQuery)
        }
        .onFirstAppear {
            viewModel.getSuggestions()
        }
        .onChange(of: searchQuery) { newValue in
            viewModel.search(query: newValue)
        }
        .onChange(of: hiddenHomeSectionIDs) { _ in
            viewModel.getSuggestions()
        }
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
    }
}

private struct ClearSearchTextField: UIViewRepresentable {

    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = ClearSearchUITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.textColor = .label
        textField.tintColor = .systemPurple
        textField.font = .preferredFont(forTextStyle: .title3)
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .search
        textField.clearButtonMode = .never
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused

        if textField.text != text {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }

        (textField as? ClearSearchUITextField)?.clearEditingBackgrounds()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        @objc
        func editingChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
            (textField as? ClearSearchUITextField)?.clearEditingBackgrounds()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused.wrappedValue = true
            (textField as? ClearSearchUITextField)?.clearEditingBackgrounds()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused.wrappedValue = false
            (textField as? ClearSearchUITextField)?.clearEditingBackgrounds()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class ClearSearchUITextField: UITextField {

    override func layoutSubviews() {
        super.layoutSubviews()
        clearEditingBackgrounds()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        clearEditingBackgrounds()
        return result
    }

    func clearEditingBackgrounds() {
        clearBackground(in: self)
    }

    private func clearBackground(in view: UIView) {
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor
        view.subviews.forEach(clearBackground)
    }
}
