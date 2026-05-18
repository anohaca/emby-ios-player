//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

final class EpisodeItemViewModel: ItemViewModel {

    // MARK: - Published Episode Items

    @Published
    private(set) var seriesItem: BaseItemDto?

    @Published
    private(set) var seriesViewModel: SeriesItemViewModel?

    // MARK: - Task

    private var seriesItemTask: AnyCancellable?

    @MainActor
    override init(item: BaseItemDto) {
        super.init(item: item)
        updateSeriesViewModel(for: item)
    }

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .refresh, .backgroundRefresh:
            seriesItemTask?.cancel()

            seriesItemTask = Task {
                do {
                    let seriesItem = try await self.getSeriesItem()

                    await MainActor.run {
                        self.seriesItem = seriesItem
                        self.updateSeriesViewModel(with: seriesItem)
                    }
                } catch {
                    await MainActor.run {
                        self.logger.error("Episode series refresh failed: \(error.embyDiagnosticDescription)")
                    }
                }
            }
            .asAnyCancellable()
        default: ()
        }

        return super.respond(to: action)
    }

    // MARK: - Get Series Items

    private func getSeriesItem() async throws -> BaseItemDto {

        guard let seriesID = item.seriesID else { throw ErrorMessage("Expected series ID missing") }

        var parameters = EmbyPortItemsParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.ids = [seriesID]
        parameters.limit = 1

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.items(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        guard let seriesItem = response.items?.first else { throw ErrorMessage("Expected series item missing") }

        return HomeItemUserDataOverrideStore.applyingOverrides(
            to: seriesItem,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )
    }

    @MainActor
    private func updateSeriesViewModel(with seriesItem: BaseItemDto) {
        if let seriesViewModel, seriesViewModel.item.id == seriesItem.id {
            seriesViewModel.send(.backgroundRefresh)
            return
        }

        let seriesViewModel = SeriesItemViewModel(item: seriesItem)
        self.seriesViewModel = seriesViewModel
        seriesViewModel.send(.refresh)
    }

    @MainActor
    private func updateSeriesViewModel(for episode: BaseItemDto) {
        guard episode.seriesID != nil else { return }

        if let seriesViewModel, seriesViewModel.item.id == episode.seriesID {
            return
        }

        let seriesViewModel = SeriesItemViewModel(episode: episode)
        self.seriesViewModel = seriesViewModel
        seriesViewModel.send(.refresh)
    }
}
