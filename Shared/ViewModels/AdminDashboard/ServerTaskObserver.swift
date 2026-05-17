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

// TODO: refactor with socket implementation
// TODO: for trigger updating, could temp set new triggers
//       and set back on failure

@MainActor
@Stateful
final class ServerTaskObserver: ViewModel, Identifiable {

    @CasePathable
    enum Action {
        case start
        case stop
        case addTrigger(EmbyTaskTrigger)
        case removeTrigger(EmbyTaskTrigger)

        var transition: Transition {
            switch self {
            case .start:
                .to(.running, then: .initial)
                    .whenBackground(.observing)
            case .stop:
                .to(.initial)
            case .addTrigger, .removeTrigger:
                .background(.updating)
            }
        }
    }

    enum BackgroundState {
        case updating
        case observing
    }

    enum State {
        case error
        case initial
        case running
    }

    @Published
    var task: EmbyTaskInfo

    var id: String? {
        task.id
    }

    init(task: EmbyTaskInfo) {
        self.task = task
    }

    @Function(\Action.Cases.start)
    private func _start() async throws {
        guard let id = task.id else { return }

        try await userSession.embyClient.startTask(taskID: id)

        try await pollTaskProgress(id: id)
    }

    @Function(\Action.Cases.stop)
    private func _stop() async throws {
        guard let id = task.id else { return }

        try await userSession.embyClient.stopTask(taskID: id)

        try await pollTaskProgress(id: id)
    }

    @Function(\Action.Cases.addTrigger)
    private func _addTrigger(_ trigger: EmbyTaskTrigger) async throws {
        let updatedTriggers = (task.triggers ?? [])
            .appending(trigger)

        try await updateTriggers(updatedTriggers)
    }

    @Function(\Action.Cases.removeTrigger)
    private func _removeTrigger(_ trigger: EmbyTaskTrigger) async throws {
        let updatedTriggers = (task.triggers ?? [])
            .filtering { $0 == trigger }

        try await updateTriggers(updatedTriggers)
    }

    private func pollTaskProgress(id: String) async throws {
        while true {
            let response: EmbyTaskInfo = try await userSession.embyClient.task(
                taskID: id,
                as: EmbyTaskInfo.self
            )

            task = response

            guard response.state == .running || response.state == .cancelling else {
                break
            }

            try await Task.sleep(for: .seconds(2))
        }
    }

    private func updateTriggers(_ updatedTriggers: [EmbyTaskTrigger]) async throws {
        guard let id = task.id else { return }
        try await userSession.embyClient.updateTaskTriggers(taskID: id, body: updatedTriggers)

        task.triggers = updatedTriggers
    }
}
