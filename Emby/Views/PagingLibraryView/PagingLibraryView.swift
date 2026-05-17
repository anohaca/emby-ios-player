//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import Nuke
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

// TODO: need to think about better design for views that may not support current library display type
//       - ex: channels/albums when in portrait/landscape
//       - just have the supported view embedded in a container view?
// TODO: could bottom (defaults + stored) `onChange` copies be cleaned up?
//       - more could be cleaned up if there was a "switcher" property wrapper that takes two
//         sources and a switch and holds the current expected value
//       - or if Defaults values were moved to StoredValues and each key would return/respond to
//         what values they should have
// TODO: when there are no filters sometimes navigation bar will be clear until popped back to

/*
 Note: Currently, it is a conscious decision to not have grid posters have subtitle content.
       This is due to episodes, which have their `S_E_` subtitles, and these can be alongside
       other items that don't have a subtitle which requires the entire library to implement
       subtitle content but that doesn't look appealing. Until a solution arrives grid posters
       will not have subtitle content.
       There should be a solution since there are contexts where subtitles are desirable and/or
       we can have subtitle content for other items.

 Note: For `rememberLayout` and `rememberSort`, there are quirks for observing changes while a
       library is open and the setting has been changed. For simplicity, do not enforce observing
       changes and doing proper updates since there is complexity with what "actual" settings
       should be applied.
 */

struct PagingLibraryView<Element: Poster>: View {

    @Default(.Customization.Library.enabledDrawerFilters)
    private var enabledDrawerFilters
    @Default(.Customization.Library.rememberLayout)
    private var rememberLayout

    @Default(.Customization.Library.displayType)
    private var defaultDisplayType: LibraryDisplayType
    @Default(.Customization.Library.listColumnCount)
    private var defaultListColumnCount: Int
    @Default(.Customization.Library.posterType)
    private var defaultPosterType: PosterDisplayType

    @Namespace
    private var namespace

    @Router
    private var router

    @State
    private var layout: CollectionVGridLayout
    @State
    private var safeArea: EdgeInsets = .zero

    @StoredValue
    private var displayType: LibraryDisplayType
    @StoredValue
    private var listColumnCount: Int
    @StoredValue
    private var posterType: PosterDisplayType

    @StateObject
    private var collectionVGridProxy: CollectionVGridProxy = .init()
    @StateObject
    private var viewModel: PagingLibraryViewModel<Element>

    private let showsFilterControls: Bool

    // MARK: init

    init(
        viewModel: PagingLibraryViewModel<Element>,
        showsFilterControls: Bool = true
    ) {

        // have to set these properties manually to get proper initial layout

        self._displayType = StoredValue(.User.libraryDisplayType(parentID: viewModel.parent?.id))
        self._listColumnCount = StoredValue(.User.libraryListColumnCount(parentID: viewModel.parent?.id))
        self._posterType = StoredValue(.User.libraryPosterType(parentID: viewModel.parent?.id))

        self._viewModel = StateObject(wrappedValue: viewModel)
        self.showsFilterControls = showsFilterControls

        let defaultDisplayType = Defaults[.Customization.Library.displayType]
        let defaultListColumnCount = Defaults[.Customization.Library.listColumnCount]
        let defaultPosterType = Defaults[.Customization.Library.posterType]

        let displayType = StoredValues[.User.libraryDisplayType(parentID: viewModel.parent?.id)]
        let listColumnCount = StoredValues[.User.libraryListColumnCount(parentID: viewModel.parent?.id)]
        let posterType = StoredValues[.User.libraryPosterType(parentID: viewModel.parent?.id)]

        let initialDisplayType = Defaults[.Customization.Library.rememberLayout] ? displayType : defaultDisplayType
        let initialListColumnCount = Defaults[.Customization.Library.rememberLayout] ? listColumnCount : defaultListColumnCount
        let initialPosterType = Defaults[.Customization.Library.rememberLayout] ? posterType : defaultPosterType

        if UIDevice.isPhone {
            layout = Self.phoneLayout(
                posterType: initialPosterType,
                viewType: initialDisplayType
            )
        } else {
            layout = Self.padLayout(
                posterType: initialPosterType,
                viewType: initialDisplayType,
                listColumnCount: initialListColumnCount
            )
        }
    }

    // MARK: onSelect

    private func onSelect(_ element: Element, in namespace: Namespace.ID) {
        switch element {
        case let element as BaseItemDto:
            select(item: element, in: namespace)
        case let element as BaseItemPerson:
            select(item: BaseItemDto(person: element), in: namespace)
        default:
            assertionFailure("Used an unexpected type within a `PagingLibaryView`?")
        }
    }

    private func select(item: BaseItemDto, in namespace: Namespace.ID) {
        switch item.type {
        case .collectionFolder, .folder:
            let viewModel = ItemLibraryViewModel(parent: item, filters: .default)
            router.route(to: .library(viewModel: viewModel), in: namespace)
        default:
            router.route(to: .item(item: item), in: namespace)
        }
    }

    // MARK: layout

    // TODO: rename old "viewType" paramter to "displayType" and sort

    private static func padLayout(
        posterType: PosterDisplayType,
        viewType: LibraryDisplayType,
        listColumnCount: Int
    ) -> CollectionVGridLayout {
        switch (posterType, viewType) {
        case (.landscape, .grid):
            .minWidth(200)
        case (.portrait, .grid), (.square, .grid):
            .minWidth(150)
        case (_, .list):
            .columns(listColumnCount, insets: .zero, itemSpacing: 0, lineSpacing: 0)
        }
    }

    private static func phoneLayout(
        posterType: PosterDisplayType,
        viewType: LibraryDisplayType
    ) -> CollectionVGridLayout {
        switch (posterType, viewType) {
        case (.landscape, .grid):
            .columns(2)
        case (.portrait, .grid):
            .columns(3)
        case (.square, .grid):
            .columns(3)
        case (_, .list):
            .columns(1, insets: .zero, itemSpacing: 0, lineSpacing: 0)
        }
    }

    private static func gridImageMaxWidth(for posterType: PosterDisplayType) -> CGFloat? {
        guard UIDevice.isPhone else { return nil }

        switch posterType {
        case .landscape:
            return 220
        case .portrait, .square:
            return 150
        }
    }

    // MARK: item view

    // Note: if parent is a folders then other items will have labels,
    //       so an empty content view is necessary

    @ViewBuilder
    private func gridItemView(item: Element, posterType: PosterDisplayType) -> some View {
        PosterButton(
            item: item,
            type: posterType,
            imageMaxWidth: Self.gridImageMaxWidth(for: posterType),
            usesContextMenuPreview: false
        ) { namespace in
            onSelect(item, in: namespace)
        } label: {
            if item.showTitle {
                PosterButton<Element>.TitleContentView(title: item.displayTitle)
                    .lineLimit(1, reservesSpace: true)
            } else if viewModel.parent?.libraryType == .folder {
                PosterButton<Element>.TitleContentView(title: item.displayTitle)
                    .lineLimit(1, reservesSpace: true)
                    .hidden()
            }
        }
    }

    @ViewBuilder
    private func listItemView(item: Element, posterType: PosterDisplayType) -> some View {
        LibraryRow(
            item: item,
            posterType: posterType
        ) { namespace in
            onSelect(item, in: namespace)
        }
    }

    @ViewBuilder
    private var elementsView: some View {
        CollectionVGrid(
            uniqueElements: viewModel.elements,
            id: \.unwrappedIDHashOrZero,
            layout: layout
        ) { item in
            let displayType = Defaults[.Customization.Library.rememberLayout] ? displayType : defaultDisplayType
            let posterType = Defaults[.Customization.Library.rememberLayout] ? posterType : defaultPosterType

            switch displayType {
            case .grid:
                gridItemView(item: item, posterType: posterType)
            case .list:
                listItemView(item: item, posterType: posterType)
            }
        }
        .onReachedBottomEdge(offset: .offset(300)) {
            viewModel.send(.getNextPage)
        }
        .proxy(collectionVGridProxy)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .content:
            if viewModel.elements.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ContentUnavailableView(L10n.noItems.localizedCapitalized, systemImage: "rectangle.on.rectangle.slash")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .pagingLibraryRefreshControl(
                    isRefreshing: viewModel.backgroundStates.contains(.refresh)
                ) {
                    viewModel.send(.refresh)
                }
            } else {
                elementsView
                    .pagingLibraryRefreshControl(
                        isRefreshing: viewModel.backgroundStates.contains(.refresh)
                    ) {
                        viewModel.send(.refresh)
                    }
            }
        case .initial, .refreshing:
            ProgressView()
        default:
            AssertionFailureView("Expected view for unexpected state")
        }
    }

    // MARK: body

    // TODO: becoming too large for typechecker during development, should break up somehow

    var body: some View {
        ZStack {
            EmbyAppBackgroundView()

            switch viewModel.state {
            case .content, .initial, .refreshing:
                contentView
            case let .error(error):
                ErrorView(error: error)
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .ignoresSafeArea(.all, edges: .vertical)
        .letterPickerBar(filterViewModel: showsFilterControls ? viewModel.filterViewModel : nil)
        .onSizeChanged { _, safeArea in
            self.safeArea = safeArea
        }
        .navigationTitle(viewModel.parent?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .ifLet(showsFilterControls ? viewModel.filterViewModel : nil) { view, filterViewModel in
            view.navigationBarFilterDrawer(
                viewModel: filterViewModel,
                types: enabledDrawerFilters
            )
        }
        .onChange(of: defaultDisplayType) { newValue in
            guard !Defaults[.Customization.Library.rememberLayout] else { return }

            if UIDevice.isPhone {
                layout = Self.phoneLayout(
                    posterType: defaultPosterType,
                    viewType: newValue
                )
            } else {
                layout = Self.padLayout(
                    posterType: defaultPosterType,
                    viewType: newValue,
                    listColumnCount: defaultListColumnCount
                )
            }
        }
        .onChange(of: defaultListColumnCount) { newValue in
            guard !Defaults[.Customization.Library.rememberLayout] else { return }

            if UIDevice.isPad {
                layout = Self.padLayout(
                    posterType: defaultPosterType,
                    viewType: defaultDisplayType,
                    listColumnCount: newValue
                )
            }
        }
        .onChange(of: defaultPosterType) { newValue in
            guard !Defaults[.Customization.Library.rememberLayout] else { return }

            if UIDevice.isPhone {
                if defaultDisplayType == .list {
                    collectionVGridProxy.layout()
                } else {
                    layout = Self.phoneLayout(
                        posterType: newValue,
                        viewType: defaultDisplayType
                    )
                }
            } else {
                if defaultDisplayType == .list {
                    collectionVGridProxy.layout()
                } else {
                    layout = Self.padLayout(
                        posterType: newValue,
                        viewType: defaultDisplayType,
                        listColumnCount: defaultListColumnCount
                    )
                }
            }
        }
        .onChange(of: displayType) { newValue in
            if UIDevice.isPhone {
                layout = Self.phoneLayout(
                    posterType: posterType,
                    viewType: newValue
                )
            } else {
                layout = Self.padLayout(
                    posterType: posterType,
                    viewType: newValue,
                    listColumnCount: listColumnCount
                )
            }
        }
        .onChange(of: listColumnCount) { newValue in
            if UIDevice.isPad {
                layout = Self.padLayout(
                    posterType: posterType,
                    viewType: displayType,
                    listColumnCount: newValue
                )
            }
        }
        .onChange(of: posterType) { newValue in
            if UIDevice.isPhone {
                if displayType == .list {
                    collectionVGridProxy.layout()
                } else {
                    layout = Self.phoneLayout(
                        posterType: newValue,
                        viewType: displayType
                    )
                }
            } else {
                if displayType == .list {
                    collectionVGridProxy.layout()
                } else {
                    layout = Self.padLayout(
                        posterType: newValue,
                        viewType: displayType,
                        listColumnCount: listColumnCount
                    )
                }
            }
        }
        .onChange(of: rememberLayout) { newValue in
            let newDisplayType = newValue ? displayType : defaultDisplayType
            let newListColumnCount = newValue ? listColumnCount : defaultListColumnCount
            let newPosterType = newValue ? posterType : defaultPosterType

            if UIDevice.isPhone {
                layout = Self.phoneLayout(
                    posterType: newPosterType,
                    viewType: newDisplayType
                )
            } else {
                layout = Self.padLayout(
                    posterType: newPosterType,
                    viewType: newDisplayType,
                    listColumnCount: newListColumnCount
                )
            }
        }
        .onChange(of: viewModel.filterViewModel?.currentFilters) { newValue in
            guard let newValue, let id = viewModel.parent?.id else { return }

            if Defaults[.Customization.Library.rememberSort] {
                let newStoredFilters = StoredValues[.User.libraryFilters(parentID: id)]
                    .mutating(\.sortBy, with: newValue.sortBy)
                    .mutating(\.sortOrder, with: newValue.sortOrder)

                StoredValues[.User.libraryFilters(parentID: id)] = newStoredFilters
            }
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .gotRandomItem(item):
                switch item {
                case let item as BaseItemDto:
                    select(item: item, in: namespace)
                case let item as BaseItemPerson:
                    select(item: BaseItemDto(person: item), in: namespace)
                default:
                    assertionFailure("Used an unexpected type within a `PagingLibaryView`?")
                }
            }
        }
        .onFirstAppear {
            if viewModel.state == .initial {
                viewModel.send(.refresh)
            }
        }
        .navigationBarMenuButton(
            isLoading: viewModel.backgroundStates.contains(.gettingNextPage) ||
                viewModel.backgroundStates.contains(.refresh)
        ) {
            if Defaults[.Customization.Library.rememberLayout] {
                LibraryViewTypeToggle(
                    posterType: $posterType,
                    viewType: $displayType,
                    listColumnCount: $listColumnCount
                )
            } else {
                LibraryViewTypeToggle(
                    posterType: $defaultPosterType,
                    viewType: $defaultDisplayType,
                    listColumnCount: $defaultListColumnCount
                )
            }

            Button(L10n.random, systemImage: "dice.fill") {
                viewModel.send(.getRandomItem)
            }
            .disabled(viewModel.elements.isEmpty)
        }
    }
}

private extension View {

    @MainActor
    func pagingLibraryRefreshControl(
        isRefreshing: Bool,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(
            PagingLibraryRefreshControlModifier(
                isRefreshing: isRefreshing,
                onRefresh: onRefresh
            )
        )
    }
}

private struct PagingLibraryRefreshControlModifier: ViewModifier {

    let isRefreshing: Bool
    let onRefresh: () -> Void

    @StateObject
    private var coordinator = PagingLibraryRefreshControlCoordinator()

    func body(content: Content) -> some View {
        content
            .introspect(
                .scrollView,
                on: .iOS(.v16, .v17, .v18, .v26),
                scope: .receiver
            ) { scrollView in
                coordinator.attach(to: scrollView, onRefresh: onRefresh)
                coordinator.update(isRefreshing: isRefreshing)
            }
            .onChange(of: isRefreshing) { newValue in
                coordinator.update(isRefreshing: newValue)
            }
    }
}

@MainActor
private final class PagingLibraryRefreshControlCoordinator: NSObject, ObservableObject {

    private let refreshControl = UIRefreshControl()
    private var onRefresh: (() -> Void)?
    private weak var scrollView: UIScrollView?

    override init() {
        super.init()

        refreshControl.addTarget(
            self,
            action: #selector(refreshControlValueChanged),
            for: .valueChanged
        )
    }

    func attach(to scrollView: UIScrollView, onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.scrollView = scrollView

        scrollView.alwaysBounceVertical = true

        if scrollView.refreshControl !== refreshControl {
            scrollView.refreshControl = refreshControl
        }
    }

    func update(isRefreshing: Bool) {
        guard !isRefreshing, refreshControl.isRefreshing else { return }

        refreshControl.endRefreshing()
    }

    @objc
    private func refreshControlValueChanged() {
        onRefresh?()
    }
}
