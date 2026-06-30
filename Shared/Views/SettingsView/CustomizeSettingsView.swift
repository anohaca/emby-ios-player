//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Engine
import Factory
import SwiftUI

struct CustomizeSettingsView: View {

    #if os(tvOS)
    typealias PlatformPicker = ListRowMenu
    #else
    typealias PlatformPicker = Picker
    #endif

    // MARK: - Home Defaults

    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Home.resumeNextUp)
    private var resumeNextUp
    @Default(.Customization.Home.maxNextUp)
    private var maxNextUp

    // MARK: - Media Defaults

    @Default(.Customization.Library.showFavorites)
    private var showFavorites
    @Default(.Customization.Library.randomImage)
    private var libraryRandomImage

    // MARK: - Library Defaults

    @Default(.Customization.Library.displayType)
    private var libraryDisplayType
    @Default(.Customization.Library.posterType)
    private var libraryPosterType
    @Default(.Customization.Library.listColumnCount)
    private var listColumnCount
    @Default(.Customization.Library.rememberLayout)
    private var rememberLibraryLayout
    @Default(.Customization.Library.rememberSort)
    private var rememberLibrarySort
    @Default(.Customization.Library.sortOptionOrder)
    private var librarySortOptionOrder
    @Default(.Customization.Library.hiddenSortOptions)
    private var libraryHiddenSortOptions

    // MARK: - Poster Defaults

    @Default(.Customization.showPosterLabels)
    private var showPosterLabels
    @Default(.Customization.nextUpPosterType)
    private var nextUpPosterType
    @Default(.Customization.recentlyAddedPosterType)
    private var recentlyAddedPosterType
    @Default(.Customization.latestInLibraryPosterType)
    private var latestInLibraryPosterType
    @Default(.Customization.similarPosterType)
    private var similarPosterType
    @Default(.Customization.searchPosterType)
    private var searchPosterType

    // MARK: - Filter Defaults

    @Default(.Customization.Library.letterPickerOrientation)
    private var letterPickerOrientation
    @Default(.Customization.Library.enabledDrawerFilters)
    private var libraryEnabledDrawerFilters
    @Default(.Customization.Library.drawerFilterOrder)
    private var libraryDrawerFilterOrder
    @Default(.Customization.Library.hiddenDrawerFilters)
    private var libraryHiddenDrawerFilters
    @Default(.Customization.Search.enabledDrawerFilters)
    private var searchEnabledDrawerFilters
    @Default(.Customization.Search.drawerFilterOrder)
    private var searchDrawerFilterOrder
    @Default(.Customization.Search.hiddenDrawerFilters)
    private var searchHiddenDrawerFilters

    // MARK: - Item Defaults

    @StoredValue(.User.itemViewAttributes)
    private var itemViewAttributes
    @StoredValue(.User.enabledTrailers)
    private var enabledTrailers
    @Default(.Customization.shouldShowMissingSeasons)
    private var shouldShowMissingSeasons
    @Default(.Customization.shouldShowMissingEpisodes)
    private var shouldShowMissingEpisodes

    // MARK: - Item View Defaults

    @Default(.Customization.itemViewType)
    private var itemViewType
    @Default(.Customization.CinematicItemViewType.usePrimaryImage)
    private var cinematicItemViewTypeUsePrimaryImage
    @Default(.Customization.Episodes.useSeriesLandscapeBackdrop)
    private var useSeriesLandscapeBackdrop

    // MARK: - Item Management Defaults

    @StoredValue(.User.enableCollectionManagement)
    private var enableCollectionManagement
    @StoredValue(.User.enableItemEditing)
    private var enableItemEditing
    @StoredValue(.User.enableItemDeletion)
    private var enableItemDeletion

    // MARK: - User Permissions

    @Injected(\.currentUserSession)
    private var userSession

    private var userPolicy: UserPolicy? {
        userSession?.user.data.policy
    }

    @Router
    private var router

    var body: some View {
        Form(systemImage: "gearshape") {
            homeSettings

            mediaSettings

            filterSettings

            librarySettings

            posterSettings

            itemSettings

            itemViewSettings

            itemManagementSettings
        }
        .navigationTitle(L10n.customize)
    }

    // MARK: - Home Settings

    @ViewBuilder
    private var homeSettings: some View {
        Section(L10n.home) {
            ChevronButton("首页类别") {
                router.route(to: .homeSectionSettings)
            }

            Toggle(L10n.nextUpRewatch, isOn: $resumeNextUp)

            StateAdapter(initialValue: false) { isPresented in
                ChevronButton {
                    isPresented.wrappedValue = true
                } label: {
                    LabeledContent(L10n.nextUpDays) {
                        if maxNextUp > 0 {
                            let duration = Duration.seconds(TimeInterval(maxNextUp))
                            return Text(duration, format: .units(allowed: [.days], width: .abbreviated))
                        } else {
                            return Text(L10n.disabled)
                        }
                    }
                }
                .alert(
                    L10n.nextUpDays,
                    isPresented: isPresented
                ) {
                    TextField(
                        L10n.days,
                        value: $maxNextUp,
                        format: .dayInterval(range: 0 ... 1000)
                    )
                    .keyboardType(.numberPad)
                } message: {
                    Text(L10n.nextUpDaysDescription)
                }
            }
        }
    }

    // MARK: - Media Settings

    @ViewBuilder
    private var mediaSettings: some View {
        Section(L10n.media) {
            Toggle(L10n.favorites, isOn: $showFavorites)

            Toggle(L10n.randomImage, isOn: $libraryRandomImage)
        }
    }

    // MARK: - Filter Settings

    @ViewBuilder
    private var filterSettings: some View {
        Section(L10n.filters) {
            PlatformPicker(L10n.letterPicker, selection: $letterPickerOrientation)

            ChevronButton("影视库筛选栏") {
                router.route(
                    to: .itemFilterDrawerSelector(
                        order: libraryDrawerFilterOrderBinding,
                        hidden: libraryHiddenDrawerFiltersBinding
                    )
                )
            }

            ChevronButton("搜索页筛选栏") {
                router.route(
                    to: .itemFilterDrawerSelector(
                        order: searchDrawerFilterOrderBinding,
                        hidden: searchHiddenDrawerFiltersBinding
                    )
                )
            }

            ChevronButton(L10n.sort) {
                router.route(
                    to: .itemSortOptionSelector(
                        order: librarySortOptionOrderBinding,
                        hidden: libraryHiddenSortOptionsBinding
                    )
                )
            }
        }
    }

    private var libraryDrawerFilterOrderBinding: Binding<[ItemFilterType]> {
        Binding {
            libraryDrawerFilterOrder
        } set: { newValue in
            libraryDrawerFilterOrder = newValue
            syncEnabledDrawerFilters(
                order: newValue,
                hidden: libraryHiddenDrawerFilters,
                enabled: $libraryEnabledDrawerFilters
            )
        }
    }

    private var libraryHiddenDrawerFiltersBinding: Binding<[ItemFilterType]> {
        Binding {
            libraryHiddenDrawerFilters
        } set: { newValue in
            libraryHiddenDrawerFilters = newValue
            syncEnabledDrawerFilters(
                order: libraryDrawerFilterOrder,
                hidden: newValue,
                enabled: $libraryEnabledDrawerFilters
            )
        }
    }

    private var searchDrawerFilterOrderBinding: Binding<[ItemFilterType]> {
        Binding {
            searchDrawerFilterOrder
        } set: { newValue in
            searchDrawerFilterOrder = newValue
            syncEnabledDrawerFilters(
                order: newValue,
                hidden: searchHiddenDrawerFilters,
                enabled: $searchEnabledDrawerFilters
            )
        }
    }

    private var searchHiddenDrawerFiltersBinding: Binding<[ItemFilterType]> {
        Binding {
            searchHiddenDrawerFilters
        } set: { newValue in
            searchHiddenDrawerFilters = newValue
            syncEnabledDrawerFilters(
                order: searchDrawerFilterOrder,
                hidden: newValue,
                enabled: $searchEnabledDrawerFilters
            )
        }
    }

    private var librarySortOptionOrderBinding: Binding<[ItemSortBy]> {
        Binding {
            librarySortOptionOrder
        } set: { newValue in
            librarySortOptionOrder = newValue
            libraryHiddenSortOptions = libraryHiddenSortOptions.filter { newValue.contains($0) }
        }
    }

    private var libraryHiddenSortOptionsBinding: Binding<[ItemSortBy]> {
        Binding {
            libraryHiddenSortOptions
        } set: { newValue in
            libraryHiddenSortOptions = newValue
        }
    }

    private func syncEnabledDrawerFilters(
        order: [ItemFilterType],
        hidden: [ItemFilterType],
        enabled: Binding<[ItemFilterType]>
    ) {
        let normalizedOrder = order.filter { ItemFilterType.allCases.contains($0) } +
            ItemFilterType.allCases.filter { !order.contains($0) }
        let hiddenSet = Set(hidden)
        enabled.wrappedValue = normalizedOrder.filter { !hiddenSet.contains($0) }
    }

    // MARK: - Library Settings

    @ViewBuilder
    private var librarySettings: some View {
        Section(L10n.libraries) {
            PlatformPicker(L10n.posters, selection: $libraryPosterType)

            PlatformPicker(L10n.defaultLayout, selection: $libraryDisplayType)

            if libraryDisplayType == .list, UIDevice.isPad || UIDevice.isTV {
                Stepper(L10n.columns, value: $listColumnCount, in: 1 ... 3, step: 1) {
                    LabeledContent(
                        L10n.columns,
                        value: listColumnCount.description
                    )
                }
            }

            Toggle(L10n.rememberLayout, isOn: $rememberLibraryLayout)

            Toggle(L10n.rememberSorting, isOn: $rememberLibrarySort)
        }
    }

    // MARK: - Poster Settings

    @ViewBuilder
    private var posterSettings: some View {
        Section(L10n.posters) {
            Toggle(L10n.showPosterLabels, isOn: $showPosterLabels)

            ChevronButton(L10n.indicators) {
                router.route(to: .indicatorSettings)
            }

            PlatformPicker(L10n.nextUp, selection: $nextUpPosterType)

            PlatformPicker(L10n.recentlyAdded, selection: $recentlyAddedPosterType)

            PlatformPicker(L10n.latestWithString(L10n.library.localizedLowercase), selection: $latestInLibraryPosterType)

            PlatformPicker(L10n.recommended, selection: $similarPosterType)

            PlatformPicker(L10n.search, selection: $searchPosterType)
        }
    }

    // MARK: - Item Settings

    @ViewBuilder
    private var itemSettings: some View {
        Section(L10n.items) {
            ChevronButton(L10n.mediaAttributes) {
                router.route(to: .itemViewAttributes(selection: $itemViewAttributes))
            }

            PlatformPicker(L10n.enabledTrailers, selection: $enabledTrailers)

            Toggle(L10n.showMissingSeasons, isOn: $shouldShowMissingSeasons)

            Toggle(L10n.showMissingEpisodes, isOn: $shouldShowMissingEpisodes)
        }
    }

    // MARK: - Item View Settings

    @ViewBuilder
    private var itemViewSettings: some View {
        if UIDevice.isPhone {
            Section {
                PlatformPicker(L10n.type, selection: $itemViewType)

                if itemViewType == .cinematic {
                    Toggle(L10n.usePrimaryImage, isOn: $cinematicItemViewTypeUsePrimaryImage)
                }

                Toggle(L10n.useSeriesImageForEpisodes, isOn: $useSeriesLandscapeBackdrop)
            } header: {
                Text(L10n.itemView)
            } footer: {
                if itemViewType == .cinematic {
                    Text(L10n.usePrimaryImageDescription)
                }
            }
        }
    }

    // MARK: - Item Management Settings

    @ViewBuilder
    private var itemManagementSettings: some View {
        if userPolicy?.isAdministrator == true ||
            userPolicy?.enableCollectionManagement == true ||
            userPolicy?.enableContentDeletion == true ||
            userPolicy?.enableContentDeletionFromFolders?.isNotEmpty == true
        {
            Section(L10n.itemManagement) {

                if userPolicy?.isAdministrator == true ||
                    userPolicy?.enableCollectionManagement == true
                {
                    Toggle(L10n.editCollections, isOn: $enableCollectionManagement)
                }

                // Does NOT include subtitle / lyric editing
                if userPolicy?.isAdministrator == true {
                    Toggle(L10n.editMedia, isOn: $enableItemEditing)
                }

                if userPolicy?.enableContentDeletion == true ||
                    userPolicy?.enableContentDeletionFromFolders?.isNotEmpty == true
                {
                    // TODO: Enable when tvOS Deletion is available
                    if !UIDevice.isTV {
                        Toggle(L10n.deleteMedia, isOn: $enableItemDeletion)
                    }
                }
            }
        }
    }
}
