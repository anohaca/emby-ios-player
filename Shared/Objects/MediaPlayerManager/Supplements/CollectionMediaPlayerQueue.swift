//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import SwiftUI

/// Keeps the playable members of a collection together while one of them is
/// playing. Unlike the episode queue, the order comes from the collection
/// view, so movies and ordinary videos can use the same next/previous controls.
@MainActor
final class CollectionMediaPlayerQueue: ViewModel, MediaPlayerQueue {

    private static let playableKinds: Set<BaseItemKind> = [
        .episode,
        .movie,
        .musicVideo,
        .video,
    ]

    let displayTitle: String = L10n.collection
    let id: String = "CollectionMediaPlayerQueue"

    @Published
    var nextItem: MediaPlayerItemProvider?
    @Published
    var previousItem: MediaPlayerItemProvider?

    lazy var nextItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $nextItem
    lazy var previousItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $previousItem

    private let items: [BaseItemDto]
    private var currentItemID: String
    private var playbackItemCancellable: AnyCancellable?

    private struct EmptyOverlay: PlatformView {
        var iOSView: some View { EmptyView() }
        var tvOSView: some View { EmptyView() }
    }

    static func make(
        items: [BaseItemDto],
        currentItem: BaseItemDto
    ) -> CollectionMediaPlayerQueue? {
        let playableItems = Self.uniquePlayableItems(items)
        guard playableItems.count > 1,
              let currentItemID = currentItem.id,
              playableItems.contains(where: { $0.id == currentItemID })
        else {
            return nil
        }

        return CollectionMediaPlayerQueue(
            items: playableItems,
            currentItemID: currentItemID
        )
    }

    private init(items: [BaseItemDto], currentItemID: String) {
        self.items = items
        self.currentItemID = currentItemID
        super.init()
        updateAdjacentItems()
    }

    weak var manager: MediaPlayerManager? {
        didSet {
            playbackItemCancellable = nil
            guard let manager else { return }
            playbackItemCancellable = manager.$playbackItem
                .sink { [weak self] playbackItem in
                    guard let item = playbackItem?.baseItem,
                          let itemID = item.id,
                          self?.items.contains(where: { $0.id == itemID }) == true
                    else { return }
                    self?.currentItemID = itemID
                    self?.updateAdjacentItems()
                }
        }
    }

    @Published
    var hasNextItem: Bool = false
    @Published
    var hasPreviousItem: Bool = false

    lazy var hasNextItemPublisher: Published<Bool>.Publisher = $hasNextItem
    lazy var hasPreviousItemPublisher: Published<Bool>.Publisher = $hasPreviousItem

    var videoPlayerBody: some PlatformView {
        EmptyOverlay()
    }

    private func updateAdjacentItems() {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItemID }) else {
            nextItem = nil
            previousItem = nil
            hasNextItem = false
            hasPreviousItem = false
            return
        }

        let previous = currentIndex > items.startIndex ? items[items.index(before: currentIndex)] : nil
        let next = currentIndex < items.index(before: items.endIndex) ? items[items.index(after: currentIndex)] : nil
        previousItem = previous.map(Self.provider(for:))
        nextItem = next.map(Self.provider(for:))
        hasNextItem = nextItem != nil
        hasPreviousItem = previousItem != nil
    }

    private static func provider(for item: BaseItemDto) -> MediaPlayerItemProvider {
        MediaPlayerItemProvider(item: item) { item in
            try await MediaPlayerItem.build(
                for: item,
                mediaSource: item.mediaSources?.first
            )
        }
    }

    private static func uniquePlayableItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
        var seenIDs = Set<String>()
        return items.filter { item in
            guard let itemType = item.type,
                  Self.playableKinds.contains(itemType),
                  item.isPlayable,
                  let itemID = item.id
            else { return false }
            return seenIDs.insert(itemID).inserted
        }
    }
}
