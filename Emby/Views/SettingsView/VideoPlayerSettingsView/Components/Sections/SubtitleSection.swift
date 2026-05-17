//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import SwiftUI

extension VideoPlayerSettingsView {
    struct SubtitleSection: View {
        @Default(.VideoPlayer.Subtitle.subtitleFontName)
        private var subtitleFontName
        @Default(.VideoPlayer.Subtitle.subtitleSize)
        private var subtitleSize
        @Default(.VideoPlayer.Subtitle.subtitleColor)
        private var subtitleColor
        @Default(.VideoPlayer.Subtitle.subtitleBorderSize)
        private var subtitleBorderSize

        @Router
        private var router

        var body: some View {
            Section {
                ChevronButton(L10n.subtitleFont, subtitle: subtitleFontName) {
                    router.route(to: .fontPicker(selection: $subtitleFontName))
                }

                Stepper(value: $subtitleSize, in: 1 ... 20, step: 1) {
                    LabeledContent(L10n.subtitleSize) {
                        Text(subtitleSize.description)
                    }
                }

                ColorPicker(L10n.subtitleColor, selection: $subtitleColor, supportsOpacity: false)

                Stepper(value: $subtitleBorderSize, in: 0 ... 8, step: 0.5) {
                    LabeledContent("字幕轮廓") {
                        Text(Self.formatSubtitleBorderSize(subtitleBorderSize))
                    }
                }
            } header: {
                Text(L10n.subtitle)
            } footer: {
                Text(L10n.subtitlesDisclaimer)
            }
        }

        private static func formatSubtitleBorderSize(_ value: Double) -> String {
            var text = String(format: "%.1f", min(max(value, 0), 8))
            while text.last == "0" {
                text.removeLast()
            }
            if text.last == "." {
                text.removeLast()
            }
            return text
        }
    }
}
