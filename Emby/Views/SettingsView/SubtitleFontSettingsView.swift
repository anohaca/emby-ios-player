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
    @State
    private var automaticDownload = SubtitleFontManager.automaticDownloadEnabled
    @State
    private var remoteServerURL = SubtitleFontManager.remoteServerURL
    @State
    private var selectedFolders = Set(SubtitleFontManager.remoteFontFolders)
    @State
    private var remoteFonts: [SubtitleFontManager.RemoteFontEntry] = []
    @State
    private var searchText = ""
    @State
    private var isLoadingIndex = false
    @State
    private var downloadingFontID: String?
    @State
    private var isBrowsingFolders = false
    @State
    private var indexProgress = SubtitleFontManager.IndexProgress(scannedFolders: 0, indexedFonts: 0)

    private var searchResults: [SubtitleFontManager.RemoteFontEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return remoteFonts.lazy.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.path.localizedCaseInsensitiveContains(query)
        }.prefix(100).map { $0 }
    }

    private var allowedContentTypes: [UTType] {
        ["ttf", "otf", "ttc", "otc"].compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        Form {
            Section {
                Toggle("自动下载缺失字体", isOn: $automaticDownload)
                    .onChange(of: automaticDownload) { value in
                        SubtitleFontManager.automaticDownloadEnabled = value
                    }

                ClearFontSearchField(text: $remoteServerURL, placeholder: "OpenList 服务器地址")
                    .frame(maxWidth: .infinity)
            } header: {
                Text("自动匹配")
            } footer: {
                Text("自动匹配只使用已经手动建立的索引，不会自行扫描 OpenList。")
            }

            Section {
                ForEach(selectedFolders.sorted(), id: \.self) { folder in
                    HStack {
                        Label(folder, systemImage: "folder")
                            .lineLimit(2)
                        Spacer()
                        Button(role: .destructive) {
                            selectedFolders.remove(folder)
                            remoteFonts = []
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button {
                    SubtitleFontManager.remoteServerURL = remoteServerURL
                    isBrowsingFolders = true
                } label: {
                    Label("添加字体文件夹", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("字体文件夹")
            } footer: {
                Text("可从同一 OpenList 服务器选择一个或多个文件夹。只有这些文件夹会被递归索引。")
            }

            Section {
                LabeledContent("字体数量") {
                    if isLoadingIndex {
                        ProgressView()
                    } else {
                        Text(remoteFonts.count.formatted())
                    }
                }

                if isLoadingIndex {
                    LabeledContent("已扫描文件夹") {
                        Text(indexProgress.scannedFolders.formatted())
                    }
                    LabeledContent("已发现字体") {
                        Text(indexProgress.indexedFonts.formatted())
                    }
                }

                Button {
                    startIndexing()
                } label: {
                    if isLoadingIndex {
                        HStack {
                            ProgressView()
                            Text("正在建立索引")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("开始索引")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoadingIndex || selectedFolders.isEmpty)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                    dimensions.width
                }

                if remoteFonts.isNotEmpty {
                    ClearFontSearchField(text: $searchText, placeholder: "搜索字体名称")
                        .frame(maxWidth: .infinity)
                }

                if !searchText.isEmpty, searchResults.isEmpty, !isLoadingIndex {
                    Text("没有匹配的字体")
                        .foregroundStyle(.secondary)
                }

                ForEach(searchResults) { font in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(font.name)
                            Text(font.isCompact ? "精简包" : "完整包")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if downloadingFontID == font.id {
                            ProgressView()
                        } else if SubtitleFontManager.importedFonts.contains(where: {
                            $0.lastPathComponent == font.name
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                download(font)
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("远程字体索引")
            } footer: {
                Text("索引只在点击“开始索引”后更新。搜索最多显示前 100 个结果。")
            }

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
        .onDisappear {
            saveRemoteConfiguration()
        }
        .onChange(of: selectedFolders) { folders in
            if folders != Set(SubtitleFontManager.remoteFontFolders) {
                remoteFonts = []
                searchText = ""
            }
        }
        .onChange(of: remoteServerURL) { value in
            if value != SubtitleFontManager.remoteServerURL {
                remoteFonts = []
                searchText = ""
            }
        }
        .task {
            await loadCachedIndex()
        }
        .sheet(isPresented: $isBrowsingFolders) {
            OpenListFontFolderPicker(selection: $selectedFolders)
        }
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
        .alert("字体操作失败", isPresented: Binding(
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

    @MainActor
    private func loadCachedIndex() async {
        guard remoteFonts.isEmpty else { return }
        remoteFonts = (try? await SubtitleFontManager.remoteFontEntries()) ?? []
    }

    private func saveRemoteConfiguration() {
        SubtitleFontManager.remoteServerURL = remoteServerURL
        SubtitleFontManager.remoteFontFolders = Array(selectedFolders)
    }

    private func startIndexing() {
        saveRemoteConfiguration()
        remoteFonts = []
        searchText = ""
        indexProgress = .init(scannedFolders: 0, indexedFonts: 0)
        isLoadingIndex = true
        Task {
            do {
                let entries = try await SubtitleFontManager.rebuildRemoteFontIndex { progress in
                    Task { @MainActor in
                        indexProgress = progress
                    }
                }
                await MainActor.run {
                    remoteFonts = entries
                    indexProgress = .init(
                        scannedFolders: indexProgress.scannedFolders,
                        indexedFonts: entries.count
                    )
                    isLoadingIndex = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingIndex = false
                }
            }
        }
    }

    private func download(_ font: SubtitleFontManager.RemoteFontEntry) {
        downloadingFontID = font.id
        Task {
            do {
                _ = try await SubtitleFontManager.installRemoteFont(font)
                await MainActor.run {
                    fonts = SubtitleFontManager.importedFonts
                    downloadingFontID = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    downloadingFontID = nil
                }
            }
        }
    }
}

private struct OpenListFontFolderPicker: View {

    @Environment(\.dismiss)
    private var dismiss

    @Binding var selection: Set<String>

    var body: some View {
        NavigationStack {
            OpenListFontFolderBrowser(
                path: "/",
                selection: $selection,
                onDone: { dismiss() }
            )
        }
    }
}

private struct OpenListFontFolderBrowser: View {

    let path: String
    @Binding var selection: Set<String>
    let onDone: () -> Void

    @State private var folders: [SubtitleFontManager.RemoteFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LabeledContent("当前位置") {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if path != "/" {
                    Button {
                        toggle(path)
                    } label: {
                        Label(
                            selection.contains(path) ? "取消选择当前文件夹" : "选择当前文件夹",
                            systemImage: selection.contains(path) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }

            Section("子文件夹") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if folders.isEmpty {
                    Text("没有子文件夹")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folders) { folder in
                        HStack(spacing: 12) {
                            Button {
                                toggle(folder.path)
                            } label: {
                                Image(systemName: selection.contains(folder.path) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(folder.path) ? .purple : .secondary)
                            }
                            .buttonStyle(.borderless)

                            NavigationLink {
                                OpenListFontFolderBrowser(
                                    path: folder.path,
                                    selection: $selection,
                                    onDone: onDone
                                )
                            } label: {
                                Label(folder.name, systemImage: "folder")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(path == "/" ? "选择字体文件夹" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成", action: onDone)
            }
        }
        .task {
            await loadFolders()
        }
        .alert("无法读取文件夹", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func toggle(_ path: String) {
        if selection.contains(path) {
            selection.remove(path)
        } else {
            selection.insert(path)
        }
    }

    @MainActor
    private func loadFolders() async {
        isLoading = true
        do {
            folders = try await SubtitleFontManager.browseRemoteFolders(at: path)
        } catch {
            folders = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ClearFontSearchField: UIViewRepresentable {

    @Binding var text: String
    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let textField = ClearFontSearchUITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.textColor = .label
        textField.tintColor = .systemPurple
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .whileEditing
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        if textField.text != text {
            textField.text = text
        }
        (textField as? ClearFontSearchUITextField)?.clearEditingBackgrounds()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc
        func editingChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
            (textField as? ClearFontSearchUITextField)?.clearEditingBackgrounds()
        }
    }
}

private final class ClearFontSearchUITextField: UITextField {

    override func layoutSubviews() {
        super.layoutSubviews()
        clearEditingBackgrounds()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        clearEditingBackgrounds()
        return result
    }

    func clearEditingBackgrounds() {
        clearBackground(in: self)
    }

    private func clearBackground(in view: UIView) {
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor
        view.subviews.forEach(clearBackground)
    }
}
