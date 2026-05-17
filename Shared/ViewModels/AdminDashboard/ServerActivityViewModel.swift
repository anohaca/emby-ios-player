//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import IdentifiedCollections

// TODO: Change with PagingLibraryViewModel changes
@MainActor
final class ServerActivityViewModel: PagingLibraryViewModel<EmbyActivityLogEntry> {

    @Published
    var hasUserId: Bool? {
        didSet {
            self.send(.refresh)
        }
    }

    @Published
    var minDate: Date? {
        didSet {
            self.send(.refresh)
        }
    }

    private(set) var users: IdentifiedArrayOf<UserDto> = []

    private var userTask: AnyCancellable?

    override func respond(to action: Action) -> State {

        switch action {
        case .refresh:
            userTask?.cancel()
            userTask = Task {
                do {
                    let users = try await getUsers()

                    await MainActor.run {
                        self.users = users
                        _ = super.respond(to: action)
                    }
                } catch {
                    await MainActor.run {
                        self.send(.error(.init(L10n.unknownError)))
                    }
                }
            }
            .asAnyCancellable()

            return .refreshing
        default:
            return super.respond(to: action)
        }
    }

    override func get(page: Int) async throws -> [EmbyActivityLogEntry] {
        var parameters = EmbyPortActivityLogParameters()
        parameters.limit = pageSize
        parameters.hasUserID = hasUserId
        parameters.minDate = minDate
        parameters.startIndex = page * pageSize

        let response: EmbyPortActivityLogResponse = try await userSession.embyClient.activityLogEntries(
            queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters),
            as: EmbyPortActivityLogResponse.self
        )

        return response.items ?? []
    }

    private func getUsers() async throws -> IdentifiedArrayOf<UserDto> {
        let response: [UserDto] = try await userSession.embyClient.users(as: [UserDto].self)

        return IdentifiedArray(uniqueElements: response)
    }
}

private struct EmbyPortActivityLogResponse: Decodable {
    var items: [EmbyActivityLogEntry]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
