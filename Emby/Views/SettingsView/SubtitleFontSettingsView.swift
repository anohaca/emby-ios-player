//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UniformTypeIdentifiers

struct SubtitleFontSettingsView: View {

    @State
    private var fonts: [URL] = SubtitleFontManager.importedFonts
    @State
    private var isImporting = false
    @State
    private var errorMessage: String?

    private var allowedContentTypes: [UTType] {
        ["ttf", "otf", "ttc", "otc"].compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        Form {
            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("导入字体", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("支持 TTF、OTF、TTC 和 OTC。字体会复制到应用内，并在下次打开视频时由 libass 加载。")
            }

            Section("已导入字体") {
                if fonts.isEmpty {
                    Text("没有导入字体")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fonts, id: \.lastPathComponent) { font in
                        HStack {
                            Label(font.deletingPathExtension().lastPathComponent, systemImage: "textformat")
                            Spacer()
                            Text(font.pathExtension.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                remove(font)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("字幕字体")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            do {
                _ = try SubtitleFontManager.install(from: result.get())
                fonts = SubtitleFontManager.importedFonts
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("字体导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func remove(_ font: URL) {
        do {
            try SubtitleFontManager.remove(font)
            fonts = SubtitleFontManager.importedFonts
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
