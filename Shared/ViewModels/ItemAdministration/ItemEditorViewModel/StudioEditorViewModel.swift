//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

final class StudioEditorViewModel: ItemEditorViewModel<NameGuidPair> {

    override func searchElements(_ searchTerm: String) async throws -> [NameGuidPair] {
        let parameters = EmbyPortStudiosParameters(searchTerm: searchTerm.isEmpty ? nil : searchTerm)
        let response: EmbyPortItemsResponse<BaseItemDto> = try await userSession.embyClient.studios(
            parameters,
            as: EmbyPortItemsResponse<BaseItemDto>.self
        )

        return response.items?.map { studio in
            NameGuidPair(id: studio.id, name: studio.name)
        } ?? []
    }

    override func addComponents(_ studios: [NameGuidPair]) async throws {
        var updatedItem = item
        if updatedItem.studios == nil {
            updatedItem.studios = []
        }
        updatedItem.studios?.append(contentsOf: studios)
        try await updateItem(updatedItem)
    }

    override func removeComponents(_ studios: [NameGuidPair]) async throws {
        var updatedItem = item
        updatedItem.studios?.removeAll { studios.contains($0) }
        try await updateItem(updatedItem)
    }

    override func reorderComponents(_ studios: [NameGuidPair]) async throws {
        var updatedItem = item
        updatedItem.studios = studios
        try await updateItem(updatedItem)
    }

    override func containsElement(named name: String) -> Bool {
        item.studios?.contains { $0.name?.caseInsensitiveCompare(name) == .orderedSame } ?? false
    }

    override func matchExists(named name: String) -> Bool {
        matches.contains { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
    }
}
