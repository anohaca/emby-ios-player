//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SeriesEpisodeSelector: View {

    @ObservedObject
    var viewModel: SeriesItemViewModel

    let focusItem: BaseItemDto?

    @State
    private var didSelectInitialSeason = false
    @State
    private var selection: SeasonItemViewModel.ID?

    init(viewModel: SeriesItemViewModel, focusItem: BaseItemDto? = nil) {
        self.viewModel = viewModel
        self.focusItem = focusItem
    }

    private var selectionViewModel: SeasonItemViewModel? {
        viewModel.seasons.first(where: { $0.id == selection })
    }

    private var scrollTargetItem: BaseItemDto? {
        focusItem ?? viewModel.playButtonItem
    }

    @ViewBuilder
    private var seasonSelectorMenu: some View {
        if let seasonDisplayName = selectionViewModel?.season.displayTitle,
           viewModel.seasons.count <= 1
        {
            Text(seasonDisplayName)
                .font(.title2)
                .fontWeight(.semibold)
        } else {
            Menu {
                ForEach(viewModel.seasons, id: \.season.id) { seasonViewModel in
                    Button {
                        selection = seasonViewModel.id
                    } label: {
                        if seasonViewModel.id == selection {
                            Label(seasonViewModel.season.displayTitle, systemImage: "checkmark")
                        } else {
                            Text(seasonViewModel.season.displayTitle)
                        }
                    }
                }
            } label: {
                Label(
                    selectionViewModel?.season.displayTitle ?? .emptyDash,
                    systemImage: "chevron.down"
                )
                .labelStyle(.episodeSelector)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            seasonSelectorMenu
                .edgePadding(.horizontal)

            Group {
                if let selectionViewModel {
                    EpisodeHStack(viewModel: selectionViewModel, playButtonItem: scrollTargetItem)
                } else {
                    LoadingHStack()
                }
            }
            .transition(.opacity.animation(.linear(duration: 0.1)))
        }
        .onReceive(viewModel.playButtonItem.publisher) { newValue in
            selectInitialSeason(for: focusItem ?? newValue)
        }
        .onReceive(viewModel.$seasons) { _ in
            if didSelectInitialSeason {
                refreshSelectionIfNeeded()
            } else {
                selectInitialSeason(for: scrollTargetItem)
            }
        }
        .onChange(of: selection) { _ in
            refreshSelectionIfNeeded()
        }
        .onAppear {
            selectInitialSeason(for: scrollTargetItem)
            refreshSelectionIfNeeded()
        }
    }

    private func selectInitialSeason(for item: BaseItemDto?) {
        guard !didSelectInitialSeason else { return }
        guard viewModel.seasons.isNotEmpty else { return }
        didSelectInitialSeason = true

        if let seasonID = item?.seasonID,
           let itemSeason = viewModel.seasons.first(where: { $0.id == seasonID })
        {
            selection = itemSeason.id
        } else {
            selection = viewModel.seasons.first?.id
        }

        refreshSelectionIfNeeded()
    }

    private func refreshSelectionIfNeeded() {
        guard let selectionViewModel else { return }

        if selectionViewModel.state == .initial {
            selectionViewModel.send(.refresh)
        }
    }
}
