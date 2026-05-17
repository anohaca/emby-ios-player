//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import SwiftUI

extension ItemView {

    struct ActionButtonHStack: View {

        @Default(.accentColor)
        private var accentColor

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        @ObservedObject
        private var viewModel: ItemViewModel

        private let equalSpacing: Bool

        // MARK: - Has Trailers

        private var hasTrailers: Bool {
            if enabledTrailers.contains(.local), viewModel.localTrailers.isNotEmpty {
                return true
            }

            if enabledTrailers.contains(.external), viewModel.item.remoteTrailers?.isNotEmpty == true {
                return true
            }

            return false
        }

        // MARK: - Initializer

        init(viewModel: ItemViewModel, equalSpacing: Bool = true) {
            self.viewModel = viewModel
            self.equalSpacing = equalSpacing
        }

        // MARK: - Body

        var body: some View {
            HStack(alignment: .center, spacing: 10) {

                if viewModel.item.canBePlayed {

                    // MARK: - Toggle Played

                    let isCheckmarkSelected = viewModel.item.userData?.isPlayed == true

                    Button(L10n.played, systemImage: "checkmark") {
                        viewModel.send(.toggleIsPlayed)
                    }
                    .buttonStyle(.tintedMaterial(tint: .embyPurple, foregroundColor: .white))
                    .isSelected(isCheckmarkSelected)
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }

                if viewModel.selectedMediaSource != nil {

                    // MARK: - Select Audio

                    AudioTrackMenu(viewModel: viewModel)
                        .menuStyle(.button)
                        .frame(maxWidth: .infinity)
                        .if(!equalSpacing) { view in
                            view.aspectRatio(1, contentMode: .fit)
                        }

                    // MARK: - Select Subtitles

                    SubtitleTrackMenu(viewModel: viewModel)
                        .menuStyle(.button)
                        .frame(maxWidth: .infinity)
                        .if(!equalSpacing) { view in
                            view.aspectRatio(1, contentMode: .fit)
                        }
                }

                // MARK: - Toggle Favorite

                let isHeartSelected = viewModel.item.userData?.isFavorite == true

                Button(L10n.favorite, systemImage: isHeartSelected ? "heart.fill" : "heart") {
                    viewModel.send(.toggleIsFavorite)
                }
                .buttonStyle(.tintedMaterial(tint: .red, foregroundColor: .white))
                .isSelected(isHeartSelected)
                .frame(maxWidth: .infinity)
                .if(!equalSpacing) { view in
                    view.aspectRatio(1, contentMode: .fit)
                }

                // MARK: - Select a Version

                if let mediaSources = viewModel.playButtonItem?.mediaSources,
                   mediaSources.count > 1
                {
                    VersionMenu(
                        viewModel: viewModel,
                        mediaSources: mediaSources
                    )
                    .menuStyle(.button)
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }

                // MARK: - Watch a Trailer

                if hasTrailers {
                    TrailerMenu(
                        localTrailers: viewModel.localTrailers,
                        externalTrailers: viewModel.item.remoteTrailers ?? []
                    )
                    .menuStyle(.button)
                    .frame(maxWidth: .infinity)
                    .if(!equalSpacing) { view in
                        view.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .font(.title3)
            .fontWeight(.semibold)
            .buttonStyle(.material)
            .labelStyle(.iconOnly)
        }

        private struct AudioTrackMenu: View {

            @ObservedObject
            var viewModel: ItemViewModel

            private var audioStreams: [MediaStream] {
                viewModel.selectedMediaSource?.audioStreams ?? []
            }

            private var selectedAudioStreamBinding: Binding<Int?> {
                Binding(
                    get: { viewModel.selectedAudioStreamIndex },
                    set: { viewModel.send(.selectAudioStream($0)) }
                )
            }

            private var systemImage: String {
                audioStreams.isEmpty ? "speaker.slash" : VideoPlayerActionButton.audio.systemImage
            }

            var body: some View {
                Menu(L10n.audio, systemImage: systemImage) {
                    if audioStreams.isEmpty {
                        Button(L10n.none, systemImage: "speaker.slash") {}
                            .disabled(true)
                    } else {
                        Picker(L10n.audio, selection: selectedAudioStreamBinding) {
                            ForEach(audioStreams, id: \.index) { stream in
                                Text(stream.trackSelectionTitle)
                                    .tag(stream.index as Int?)
                            }
                        }
                    }
                }
                .disabled(audioStreams.isEmpty)
            }
        }

        private struct SubtitleTrackMenu: View {

            @ObservedObject
            var viewModel: ItemViewModel

            private var subtitleStreams: [MediaStream] {
                viewModel.selectedMediaSource?.subtitleStreams ?? []
            }

            private var selectedSubtitleStreamBinding: Binding<Int?> {
                Binding(
                    get: { viewModel.selectedSubtitleStreamIndex },
                    set: { viewModel.send(.selectSubtitleStream($0)) }
                )
            }

            private var systemImage: String {
                guard viewModel.selectedSubtitleStreamIndex != -1 else {
                    return VideoPlayerActionButton.subtitles.secondarySystemImage
                }
                return VideoPlayerActionButton.subtitles.systemImage
            }

            var body: some View {
                Menu(L10n.subtitles, systemImage: systemImage) {
                    Picker(L10n.subtitles, selection: selectedSubtitleStreamBinding) {
                        Text(L10n.none)
                            .tag(-1 as Int?)

                        ForEach(subtitleStreams, id: \.index) { stream in
                            Text(stream.trackSelectionTitle)
                                .tag(stream.index as Int?)
                        }
                    }
                }
                .disabled(subtitleStreams.isEmpty)
            }
        }
    }
}

private extension MediaStream {

    var trackSelectionTitle: String {
        let primary = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let primary, !primary.isEmpty {
            return primary
        }

        var parts: [String] = []
        if let language = language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            parts.append(language.uppercased())
        }
        if let codec = codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        if let channelLayout = channelLayout?.trimmingCharacters(in: .whitespacesAndNewlines), !channelLayout.isEmpty {
            parts.append(channelLayout)
        } else if let channels {
            parts.append("\(channels)ch")
        }
        if isDefault == true {
            parts.append("Default")
        }
        if isForced == true {
            parts.append("Forced")
        }

        return parts.isEmpty ? L10n.unknown : parts.joined(separator: " · ")
    }
}
