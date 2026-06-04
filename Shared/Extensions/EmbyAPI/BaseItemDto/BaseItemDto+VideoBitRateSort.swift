//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

extension [BaseItemDto] {

    func sortedByVideoBitRateIfNeeded(filters: ItemFilterCollection?) -> [BaseItemDto] {
        guard let filters, filters.isVideoBitRateSort else { return self }

        let descending = filters.sortOrder.first == .descending

        return sorted { lhs, rhs in
            let lhsBitRate = lhs.videoBitRateSortValue
            let rhsBitRate = rhs.videoBitRateSortValue

            switch (lhsBitRate, rhsBitRate) {
            case let (lhsBitRate?, rhsBitRate?):
                return descending ? lhsBitRate > rhsBitRate : lhsBitRate < rhsBitRate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.displayTitle < rhs.displayTitle
            }
        }
    }
}

private extension BaseItemDto {

    var videoBitRateSortValue: Int? {
        mediaSources?
            .lazy
            .compactMap(\.bitrate)
            .max()
    }
}
