//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

final class RemoteImageInfoViewModel: PagingLibraryViewModel<RemoteImageInfo> {

    // Image providers come from the paging call
    @Published
    private(set) var providers: [String] = []

    @Published
    var includeAllLanguages: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.send(.refresh)
            }
        }
    }

    @Published
    var provider: String? = nil {
        didSet {
            DispatchQueue.main.async {
                self.send(.refresh)
            }
        }
    }

    let imageType: ImageType

    init(imageType: ImageType, parent: BaseItemDto) {

        self.imageType = imageType

        super.init(parent: parent)
    }

    override func get(page: Int) async throws -> [RemoteImageInfo] {
        guard let itemID = parent?.id else { return [] }

        var parameters = EmbyPortRemoteImagesParameters()
        parameters.isIncludeAllLanguages = includeAllLanguages
        parameters.limit = pageSize
        parameters.providerName = provider
        parameters.startIndex = page * pageSize
        parameters.type = imageType

        let response: EmbyPortRemoteImagesResponse = try await userSession.embyClient.remoteImages(
            itemID: itemID,
            queryItems: EmbyPortQueryItemBuilder.queryItems(from: parameters),
            as: EmbyPortRemoteImagesResponse.self
        )

        await MainActor.run {
            providers = response.providers ?? []
        }

        return response.images ?? []
    }
}

private struct EmbyPortRemoteImagesResponse: Decodable {
    var images: [RemoteImageInfo]?
    var providers: [String]?

    enum CodingKeys: String, CodingKey {
        case images = "Images"
        case providers = "Providers"
    }
}
