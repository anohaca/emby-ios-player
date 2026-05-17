//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Pulse

private let redactedMessage = "<Redacted by Emby>"
private let passwordKeysToRedact = [
    "CurrentPassword",
    "CurrentPw",
    "NewPw",
    "Pw",
    "currentPassword",
    "currentPw",
    "newPw",
    "pw",
]

extension NetworkLogger {

    static func emby() -> NetworkLogger {
        var configuration = NetworkLogger.Configuration()

        configuration.willHandleEvent = { event -> LoggerStore.Event? in
            if case var LoggerStore.Event.networkTaskCompleted(task) = event {
                guard let url = task.originalRequest.url,
                      let requestBody = task.requestBody
                else {
                    return event
                }

                let pathComponents = url.pathComponents

                if pathComponents.last == "AuthenticateByName",
                   let redactedBody = Self.redactJSONBody(requestBody, keys: ["Pw", "pw"])
                {
                    task.requestBody = redactedBody

                    return LoggerStore.Event.networkTaskCompleted(task)
                }

                if pathComponents.last == "Password",
                   let redactedBody = Self.redactJSONBody(requestBody, keys: passwordKeysToRedact, removing: ["IsResetPassword", "isResetPassword"])
                {
                    task.requestBody = redactedBody

                    return LoggerStore.Event.networkTaskCompleted(task)
                }
            }

            return event
        }

        return NetworkLogger(configuration: configuration)
    }

    private static func redactJSONBody(_ data: Data, keys: [String], removing removedKeys: [String] = []) -> Data? {
        guard var body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in keys where body[key] != nil {
            body[key] = redactedMessage
        }

        for key in removedKeys {
            body.removeValue(forKey: key)
        }

        return try? JSONSerialization.data(withJSONObject: body)
    }
}
