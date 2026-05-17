//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import Foundation

final class ChannelLibraryViewModel: PagingLibraryViewModel<ChannelProgram> {

    override func get(page: Int) async throws -> [ChannelProgram] {

        var parameters = EmbyPortLiveTVChannelsParameters()
        parameters.fields = .MinimumFields
        parameters.sortBy = [ItemSortBy.name]

        parameters.limit = pageSize
        parameters.startIndex = page * pageSize

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.liveTVChannels(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return try await getPrograms(for: response.items ?? [])
    }

    private func getPrograms(for channels: [BaseItemDto]) async throws -> [ChannelProgram] {

        guard let minEndDate = Calendar.current.date(byAdding: .hour, value: -1, to: .now),
              let maxStartDate = Calendar.current.date(byAdding: .hour, value: 6, to: .now) else { return [] }

        var parameters = EmbyPortLiveTVProgramsParameters()
        parameters.channelIDs = channels.compactMap(\.id)
        parameters.maxStartDate = maxStartDate
        parameters.minEndDate = minEndDate
        parameters.sortBy = [ItemSortBy.startDate]

        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.liveTVPrograms(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        let groupedPrograms = (response.items ?? [])
            .grouped { program in
                channels.first(where: { $0.id == program.channelID })
            }

        return channels
            .reduce(into: [:]) { partialResult, channel in
                partialResult[channel] = (groupedPrograms[channel] ?? [])
                    .sorted(using: \.startDate)
            }
            .map(ChannelProgram.init)
            .sorted(using: \.channel.name)
    }
}
