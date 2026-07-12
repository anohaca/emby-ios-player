//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//

import Defaults
import SwiftUI

struct SubtitleSettingsView: View {

    @Default(.VideoPlayer.Subtitle.defaultSubtitleLanguage)
    private var defaultSubtitleLanguage
    @Default(.VideoPlayer.Subtitle.convertTraditionalChineseSubtitles)
    private var convertTraditionalChineseSubtitles

    @Router
    private var router

    var body: some View {
        Form {
            Section {
                Picker("默认字幕语言", selection: $defaultSubtitleLanguage) {
                    ForEach(MediaTrackLanguagePreference.allCases, id: \.self) { language in
                        Text(language.displayTitle)
                            .tag(language)
                    }
                }
            } footer: {
                Text("选择“自动”时会优先中文字幕，找不到再使用服务器或文件默认字幕。")
            }

            Section {
                Toggle("繁体字幕转简体", isOn: $convertTraditionalChineseSubtitles)

                ChevronButton("字幕字体") {
                    router.route(to: .subtitleFontSettings)
                }
            } header: {
                Text("字幕兼容")
            } footer: {
                Text("仅文本字幕会转换，PGS/VobSub 等图片字幕保持原样。")
            }

            VideoPlayerSettingsView.SubtitleSection()
        }
        .navigationTitle(L10n.subtitle)
    }
}
