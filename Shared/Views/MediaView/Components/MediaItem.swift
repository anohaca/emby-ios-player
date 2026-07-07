//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// Note: the design reason to not have a local label always on top
//       is to have the same failure/empty color for all views

extension MediaView {

    // TODO: custom view for folders and tv (allow customization?)
    //       - differentiate between what media types are Emby-player only
    //         which would allow some cleanup
    //       - allow server or random view per library?
    // TODO: if local label on image, also needs to be in blurhash placeholder
    struct MediaItem: View {

        @Default(.Customization.Library.randomImage)
        private var useRandomImage

        @ObservedObject
        private var viewModel: MediaViewModel

        @Namespace
        private var namespace

        @State
        private var imageSources: [ImageSource] = []

        private let action: (Namespace.ID) -> Void
        private let mediaType: MediaViewModel.MediaType

        init(
            viewModel: MediaViewModel,
            type: MediaViewModel.MediaType,
            action: @escaping (Namespace.ID) -> Void
        ) {
            self.viewModel = viewModel
            self.action = action
            self.mediaType = type
            self._imageSources = State(
                initialValue: MediaItemImageSourceCache.shared.imageSources(for: type) ?? Self.fallbackImageSources(for: type)
            )
        }

        private var useTitleLabel: Bool {
            useRandomImage ||
                mediaType == .downloads ||
                mediaType == .favorites
        }

        private var fallbackImageSources: [ImageSource] {
            Self.fallbackImageSources(for: mediaType)
        }

        private static func fallbackImageSources(for mediaType: MediaViewModel.MediaType) -> [ImageSource] {
            if case let MediaViewModel.MediaType.collectionFolder(item) = mediaType {
                return [item.imageSource(.primary, maxWidth: 500)]
            } else if case let MediaViewModel.MediaType.liveTV(item) = mediaType {
                return [item.imageSource(.primary, maxWidth: 500)]
            }

            return []
        }

        private func setImageSources(forceRefresh: Bool = false) {
            if !forceRefresh, let cachedImageSources = MediaItemImageSourceCache.shared.imageSources(for: mediaType) {
                setImageSourcesIfNeeded(cachedImageSources)
                return
            }

            Task { @MainActor in
                if useRandomImage {
                    do {
                        let randomImageSources = try await viewModel.randomItemImageSources(for: mediaType)
                        if randomImageSources.isNotEmpty {
                            setImageSourcesIfNeeded(randomImageSources)
                            return
                        }
                    } catch {
                        // Fall through to the library image when random items cannot provide one.
                    }
                }

                setImageSourcesIfNeeded(fallbackImageSources)
            }
        }

        private func setImageSourcesIfNeeded(_ newImageSources: [ImageSource]) {
            guard imageSources != newImageSources else { return }

            imageSources = newImageSources
            MediaItemImageSourceCache.shared.set(newImageSources, for: mediaType)
        }

        @ViewBuilder
        private var titleLabel: some View {
            Text(mediaType.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(alignment: .center)
        }

        private func titleLabelOverlay(with content: some View) -> some View {
            ZStack {
                content

                Color.black
                    .opacity(0.5)

                titleLabel
                    .foregroundStyle(.white)
            }
        }

        var body: some View {
            Button {
                action(namespace)
            } label: {
                ImageView(imageSources)
                    .image { image in
                        if useTitleLabel {
                            titleLabelOverlay(with: image)
                        } else {
                            image
                        }
                    }
                    .placeholder { imageSource in
                        titleLabelOverlay(with: DefaultPlaceholderView(blurHash: imageSource.blurHash))
                    }
                    .failure {
                        Color.secondarySystemFill
                            .opacity(0.75)
                            .overlay {
                                titleLabel
                                    .foregroundColor(.primary)
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .posterStyle(.landscape)
                    .backport
                    .matchedTransitionSource(id: "item", in: namespace)
            }
            .onFirstAppear {
                setImageSources()
            }
            .backport
            .onChange(of: useRandomImage) { _, _ in
                setImageSources(forceRefresh: true)
            }
            .buttonStyle(.card)
        }
    }
}

private final class MediaItemImageSourceCache {
    static let shared = MediaItemImageSourceCache()

    private var imageSourcesByMediaTypeID: [String: [ImageSource]] = [:]

    func imageSources(for mediaType: MediaViewModel.MediaType) -> [ImageSource]? {
        guard let cacheKey = mediaType.cacheKey else { return nil }
        return imageSourcesByMediaTypeID[cacheKey]
    }

    func set(_ imageSources: [ImageSource], for mediaType: MediaViewModel.MediaType) {
        guard let cacheKey = mediaType.cacheKey else { return }
        imageSourcesByMediaTypeID[cacheKey] = imageSources
    }
}

private extension MediaViewModel.MediaType {

    var cacheKey: String? {
        switch self {
        case let .collectionFolder(item):
            item.id.map { "collectionFolder:\($0)" }
        case .downloads:
            "downloads"
        case .favorites:
            "favorites"
        case let .liveTV(item):
            item.id.map { "liveTV:\($0)" }
        }
    }
}
