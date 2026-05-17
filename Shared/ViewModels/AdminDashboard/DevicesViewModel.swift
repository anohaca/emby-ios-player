//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import OrderedCollections
import SwiftUI

@MainActor
@Stateful
final class DevicesViewModel: ViewModel {

    @CasePathable
    enum Action {
        case refresh
        case delete(ids: Set<String>)
        case update(id: String, options: EmbyDeviceOptions)

        var transition: Transition {
            switch self {
            case .refresh:
                .loop(.refreshing)
                    .whenBackground(.refreshing)
            case .delete, .update:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case refreshing
        case updating
    }

    enum Event {
        case updated
    }

    enum State {
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var devices: [EmbyDeviceInfo] = []

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {
        let response: EmbyPortDevicesResponse = try await userSession.embyClient.devices(
            as: EmbyPortDevicesResponse.self
        )

        guard let devices = response.items else {
            return
        }

        let sortedDevices = Array(devices.sorted(using: \.dateLastActivity)
            .reversed()
        )

        self.devices = sortedDevices
    }

    @Function(\Action.Cases.update)
    private func _update(_ id: String, _ options: EmbyDeviceOptions) async throws {
        try await userSession.embyClient.updateDeviceOptions(id: id, body: options)

        let deviceIndices = devices.indices.filter { devices[$0].id == id }

        for index in deviceIndices {
            devices[index].customName = options.customName
        }

        events.send(.updated)
    }

    @Function(\Action.Cases.delete)
    private func _delete(_ ids: Set<String>) async throws {
        guard ids.isNotEmpty else { return }

        // TODO: allow deleting same-device entry, but cannot delete the same-device/same-user pair (current session)
        let deviceIdsToDelete = ids.filter { $0 != userSession.embyClient.configuration.identity.deviceID }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for deviceId in deviceIdsToDelete {
                group.addTask {
                    try await self.deleteDevice(id: deviceId)
                }
            }

            try await group.waitForAll()
        }

        devices = devices.subtracting(deviceIdsToDelete, using: \.id)
    }

    // TODO: Replace if the Emby API supports deleting in batch.
    private func deleteDevice(id: String) async throws {
        try await userSession.embyClient.deleteDevice(id: id)
    }
}

private struct EmbyPortDevicesResponse: Decodable {
    var items: [EmbyDeviceInfo]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
