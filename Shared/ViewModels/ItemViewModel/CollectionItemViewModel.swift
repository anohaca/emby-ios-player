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

@MainActor
final class CollectionItemViewModel: ItemViewModel {

    @ObservedPublisher
    var sections: OrderedDictionary<BaseItemKind, ItemLibraryViewModel>

    private let itemCollection: ItemTypeCollection

    @MainActor
    override init(item: BaseItemDto) {
        self.itemCollection = ItemTypeCollection(
            parent: item,
            itemTypes: BaseItemKind.supportedCases
                .appending(.episode)
                .appending(.person)
        )
        self._sections = ObservedPublisher(
            wrappedValue: [:],
            observing: itemCollection.$elements
        )

        super.init(item: item)

        itemCollection.$elements
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sections in
                self?.updatePlayButtonItem(from: sections)
            }
            .store(in: &cancellables)
    }

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .refresh, .backgroundRefresh:
            itemCollection.send(.refresh)
        default: ()
        }

        return super.respond(to: action)
    }

    // TODO: possibly multiple items, for image source fallbacks
    func randomItem() -> BaseItemDto? {
        // Try to exclude episodes if possible

        if itemCollection.elements.elements.count == 1 {
            return itemCollection.elements.elements.first?.value.elements.first
        }

        return itemCollection.elements
            .elements
            .shuffled()
            .filter { $0.key != .episode }
            .randomElement()?
            .value
            .elements
            .randomElement()
    }

    var playableItems: [BaseItemDto] {
        let orderedSections: [OrderedDictionary<BaseItemKind, ItemLibraryViewModel>.Elements.Element] = {
            let sections = Array(sections.elements)
            guard item.type == .boxSet else { return sections }

            return sections.enumerated()
                .sorted { lhs, rhs in
                    let lhsPriority = playableSectionPriority(lhs.element.key)
                    let rhsPriority = playableSectionPriority(rhs.element.key)
                    return lhsPriority == rhsPriority
                        ? lhs.offset < rhs.offset
                        : lhsPriority < rhsPriority
                }
                .map(\.element)
        }()

        return orderedSections
            .flatMap(\.value.elements)
            .filter { item in
                switch item.type {
                case .episode, .movie, .musicVideo, .video:
                    item.isPlayable
                default:
                    false
                }
            }
    }

    private func updatePlayButtonItem(from sections: OrderedDictionary<BaseItemKind, ItemLibraryViewModel>) {
        guard item.type == .boxSet else { return }

        let orderedSections = sections.elements.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = playableSectionPriority(lhs.element.key)
                let rhsPriority = playableSectionPriority(rhs.element.key)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                } else {
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)

        guard let firstPlayableItem = orderedSections
            .lazy
            .flatMap(\.value.elements)
            .first(where: \.isPlayable)
        else { return }

        if playButtonItem?.id != firstPlayableItem.id {
            playButtonItem = firstPlayableItem
        }
    }

    private func playableSectionPriority(_ kind: BaseItemKind) -> Int {
        switch kind {
        case .video:
            0
        case .musicVideo:
            1
        case .movie:
            2
        default:
            3
        }
    }
}
