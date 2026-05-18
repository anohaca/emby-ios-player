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

// TODO: respond properly to end of playback
//       - when item changes
// TODO: only send stop on manager stop, not per-item

class MediaProgressObserver: ViewModel, MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        willSet {
            guard newValue == nil else { return }
            sendStopReportIfNeeded(seconds: manager?.seconds)
        }

        didSet {
            guard let manager else {
                timer.stop()
                cancellables = []
                return
            }

            setup(with: manager)
        }
    }

    private let timer = PokeIntervalTimer()
    private var hasSentStart = false
    private var hasSentStop = false
    private var hasNotifiedHomeAfterServerProgress = false
    private weak var item: MediaPlayerItem?
    private var lastKnownPlaybackSeconds: Duration?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing

    init(item: MediaPlayerItem) {
        self.item = item
        super.init()
    }

    private func sendReport() {
        guard let item else { return }

        switch lastPlaybackRequestStatus {
        case .playing:
            if hasSentStart {
                sendProgressReport(for: item, seconds: manager?.seconds)
            } else {
                sendStartReport(for: item, seconds: manager?.seconds)
            }
        case .paused:
            sendProgressReport(for: item, seconds: manager?.seconds, isPaused: true)
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []
        hasSentStop = false
        recordPlaybackSeconds(manager.seconds)

        timer.sink { [weak self] in
            self?.sendReport()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.actions
            .sink { [weak self] in self?.didReceive(action: $0) }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] in self?.playbackRequestStatusDidChange($0) }
            .store(in: &cancellables)

        manager.secondsBox.$value
            .sink { [weak self] in self?.recordPlaybackSeconds($0) }
            .store(in: &cancellables)
    }

    private func playbackRequestStatusDidChange(_ newStatus: MediaPlayerManager.PlaybackRequestStatus) {
        timer.poke()
        lastPlaybackRequestStatus = newStatus
    }

    // TODO: respond to error
    // TODO: respond properly to ended
    private func didReceive(action: MediaPlayerManager._Action) {
        switch action {
        case .stop:
            sendStopReportIfNeeded(seconds: manager?.seconds)
            timer.stop()
            cancellables = []
            item = nil
        default: ()
        }
    }

    private func sendStopReportIfNeeded(seconds: Duration?) {
        guard !hasSentStop, let item else { return }
        sendStopReport(for: item, seconds: stopReportSeconds(from: seconds))
        hasSentStop = true
    }

    private func sendStartReport(for item: MediaPlayerItem, seconds: Duration?) {

        recordResumeRecency(for: item, notifyHome: true)

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        let client = userSession.embyClient
        let audioStreamIndex = item.selectedAudioStreamIndex
        let itemID = item.baseItem.id
        let mediaSourceID = item.mediaSource.id
        let playSessionID = item.playSessionID
        let positionTicks = seconds.map { Int64($0.ticks) }
        let subtitleStreamIndex = item.selectedSubtitleStreamIndex

        Task { [weak self] in
            try? await client.reportPlaybackStarted(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )

            self?.hasSentStart = true
        }
    }

    private func sendStopReport(for item: MediaPlayerItem, seconds: Duration?) {

        recordResumeRecency(for: item, notifyHome: true)

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        let client = userSession.embyClient
        let itemID = item.baseItem.id
        let mediaSourceID = item.mediaSource.id
        let playSessionID = item.playSessionID
        let positionTicks = seconds.map { Int64($0.ticks) }

        #if DEBUG
        NSLog(
            "EmbyPlaybackProgress stop item=%@ seconds=%.3f ticks=%@",
            itemID ?? "<nil>",
            seconds?.seconds ?? -1,
            positionTicks.map(String.init) ?? "<nil>"
        )
        #endif

        Task {
            try? await client.reportPlaybackStopped(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks
            )

            await MainActor.run {
                if let itemID {
                    Notifications[.resumeItemRecencyDidChange].post(itemID)
                }
                self.notifyRelatedMetadataShouldRefresh(for: item)
            }
        }
    }

    private func recordPlaybackSeconds(_ seconds: Duration) {
        guard seconds >= .zero else { return }

        if seconds > .zero || lastKnownPlaybackSeconds == nil {
            lastKnownPlaybackSeconds = seconds
        }
    }

    private func stopReportSeconds(from seconds: Duration?) -> Duration? {
        if let seconds, seconds > .zero {
            return seconds
        }

        return lastKnownPlaybackSeconds ?? seconds
    }

    private func sendProgressReport(for item: MediaPlayerItem, seconds: Duration?, isPaused: Bool = false) {

        recordResumeRecency(for: item)

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        let client = userSession.embyClient
        let audioStreamIndex = item.selectedAudioStreamIndex
        let itemID = item.baseItem.id
        let mediaSourceID = item.mediaSource.id
        let playSessionID = item.playSessionID
        let positionTicks = seconds.map { Int64($0.ticks) }
        let subtitleStreamIndex = item.selectedSubtitleStreamIndex
        let shouldNotifyHomeAfterServerProgress = !hasNotifiedHomeAfterServerProgress
        hasNotifiedHomeAfterServerProgress = true

        Task {
            try? await client.reportPlaybackProgress(
                itemID: itemID,
                mediaSourceID: mediaSourceID,
                playSessionID: playSessionID,
                positionTicks: positionTicks,
                isPaused: isPaused,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )

            if shouldNotifyHomeAfterServerProgress {
                await MainActor.run {
                    if let itemID {
                        Notifications[.resumeItemRecencyDidChange].post(itemID)
                    }
                }
            }
        }
    }

    private func recordResumeRecency(for item: MediaPlayerItem, notifyHome: Bool = false) {
        HomeItemUserDataOverrideStore.clearRelatedItems(
            for: item.baseItem,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )

        ResumeItemRecencyStore.markPlayback(
            itemID: item.baseItem.id,
            serverID: userSession.server.id,
            userID: userSession.user.id
        )

        if notifyHome, let itemID = item.baseItem.id {
            Notifications[.resumeItemRecencyDidChange].post(itemID)
        }
    }

    @MainActor
    private func notifyRelatedMetadataShouldRefresh(for item: MediaPlayerItem) {
        HomeRefreshInvalidationStore.markAndPostRelatedMetadataRefresh(for: item.baseItem, userSession: userSession)
    }
}
