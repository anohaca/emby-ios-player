//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@MainActor
@Stateful
final class AddServerUserViewModel: ViewModel {

    @CasePathable
    enum Action {
        case cancel
        case add(username: String, password: String)

        var transition: Transition {
            switch self {
            case .cancel:
                .to(.initial)
            case .add:
                .to(.addingUser, then: .initial)
            }
        }
    }

    enum Event {
        case created(user: UserDto)
        case error
    }

    enum State: Hashable {
        case addingUser
        case initial
    }

    @Function(\Action.Cases.add)
    private func _add(_ username: String, _ password: String) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        let parameters = EmbyCreateUser(name: trimmedUsername)
        let response: UserDto = try await userSession.embyClient.createUser(
            body: parameters,
            as: UserDto.self
        )

        if !trimmedPassword.isEmpty {
            guard let userID = response.id else {
                throw ErrorMessage("用户已创建，但服务器没有返回用户 ID，无法设置密码。")
            }

            try await userSession.embyClient.updateUserPassword(
                userID: userID,
                body: EmbyCreatedUserPassword(
                    currentPassword: "",
                    newPassword: trimmedPassword
                )
            )
        }

        events.send(.created(user: response))
    }
}

private struct EmbyCreateUser: Encodable {
    var name: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}

private struct EmbyCreatedUserPassword: Encodable {
    var currentPassword: String
    var newPassword: String

    enum CodingKeys: String, CodingKey {
        case currentPassword = "CurrentPw"
        case newPassword = "NewPw"
    }
}
