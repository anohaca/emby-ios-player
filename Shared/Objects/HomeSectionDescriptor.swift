//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct HomeSectionDescriptor: Identifiable, Hashable, Displayable, SystemImageable {

    static let continueWatchingID = "continueWatching"
    static let nextUpID = "nextUp"
    static let recentlyAddedID = "recentlyAdded"

    private static let latestInLibraryPrefix = "latestInLibrary:"

    let id: String
    let displayTitle: String
    let systemImage: String

    static var standardSections: [HomeSectionDescriptor] {
        [
            .init(
                id: continueWatchingID,
                displayTitle: L10n.resume,
                systemImage: "play.rectangle.on.rectangle"
            ),
            .init(
                id: nextUpID,
                displayTitle: L10n.nextUp,
                systemImage: "text.line.first.and.arrowtriangle.forward"
            ),
            .init(
                id: recentlyAddedID,
                displayTitle: L10n.recentlyAdded.localizedCapitalized,
                systemImage: "clock.badge.plus"
            ),
        ]
    }

    static func latestInLibrary(id: String, title: String) -> HomeSectionDescriptor {
        .init(
            id: latestInLibraryID(id),
            displayTitle: L10n.latestWithString(title),
            systemImage: "rectangle.stack.badge.plus"
        )
    }

    static func latestInLibraryID(_ id: String) -> String {
        "\(latestInLibraryPrefix)\(id)"
    }

    static func latestInLibrarySourceID(from sectionID: String) -> String? {
        guard sectionID.hasPrefix(latestInLibraryPrefix) else { return nil }
        return String(sectionID.dropFirst(latestInLibraryPrefix.count))
    }

    static func ordered(
        _ sections: [HomeSectionDescriptor],
        using storedOrder: [String]
    ) -> [HomeSectionDescriptor] {
        let sectionsByID = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        var seen = Set<String>()

        let orderedSections = storedOrder.compactMap { id -> HomeSectionDescriptor? in
            guard seen.insert(id).inserted else { return nil }
            return sectionsByID[id]
        }

        return orderedSections + sections.filter { seen.insert($0.id).inserted }
    }
}
