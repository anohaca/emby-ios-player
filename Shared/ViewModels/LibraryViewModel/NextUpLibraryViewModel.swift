//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation

final class NextUpLibraryViewModel: PagingLibraryViewModel<BaseItemDto> {

    init() {
        super.init(parent: TitledLibraryParent(displayTitle: L10n.nextUp, id: "nextUp"))
    }

    override func get(page: Int) async throws -> [BaseItemDto] {

        let parameters = parameters(for: page)
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.nextUp(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items ?? []
    }

    private func parameters(for page: Int) -> EmbyPortNextUpParameters {

        let maxNextUp = Defaults[.Customization.Home.maxNextUp]
        var parameters = EmbyPortNextUpParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.limit = pageSize
        if maxNextUp > 0 {
            parameters.nextUpDateCutoff = Date.now.addingTimeInterval(-maxNextUp)
        }
        parameters.enableRewatching = Defaults[.Customization.Home.resumeNextUp]
        parameters.startIndex = page

        return parameters
    }
}
