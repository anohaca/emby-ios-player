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

struct HomeSectionSettingsView: View {

    @Default(.Customization.Home.sectionOrder)
    private var sectionOrder
    @Default(.Customization.Home.hiddenSectionIDs)
    private var hiddenSectionIDs
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded

    @StateObject
    private var viewModel = HomeViewModel()
    @State
    private var editMode: EditMode = .active

    @Injected(\.currentUserSession)
    private var userSession

    private struct SectionRow: Identifiable {

        let section: HomeSectionDescriptor
        let isHidden: Bool

        var id: String {
            "\(isHidden ? "disabled" : "enabled"):\(section.id)"
        }
    }

    private var sections: [HomeSectionDescriptor] {
        let dynamicSections: [HomeSectionDescriptor] = viewModel.libraries.compactMap { libraryViewModel in
            guard let id = libraryViewModel.parent?.id else { return nil }

            return HomeSectionDescriptor.latestInLibrary(
                id: id,
                title: libraryViewModel.parent?.displayTitle ?? .emptyDash
            )
        }

        return HomeSectionDescriptor.ordered(
            HomeSectionDescriptor.standardSections + dynamicSections,
            using: sectionOrder
        )
    }

    private var enabledSections: [HomeSectionDescriptor] {
        sections.filter { !isHidden($0) }
    }

    private var disabledSections: [HomeSectionDescriptor] {
        sections.filter(isHidden)
    }

    private var enabledRows: [SectionRow] {
        enabledSections.map { SectionRow(section: $0, isHidden: false) }
    }

    private var disabledRows: [SectionRow] {
        disabledSections.map { SectionRow(section: $0, isHidden: true) }
    }

    private func isHidden(_ section: HomeSectionDescriptor) -> Bool {
        if section.id == HomeSectionDescriptor.recentlyAddedID, !showRecentlyAdded {
            return true
        }

        return hiddenSectionIDs.contains(section.id)
    }

    private func setHidden(_ hidden: Bool, for section: HomeSectionDescriptor) {
        let currentOrderIDs = sections.map(\.id)
        var hiddenIDs = hiddenSectionIDs

        if hidden {
            hiddenIDs.append(section.id)
        } else {
            hiddenIDs.removeAll { $0 == section.id }
        }

        hiddenSectionIDs = uniqueIDs(hiddenIDs)

        if section.id == HomeSectionDescriptor.recentlyAddedID {
            showRecentlyAdded = !hidden
        }

        sectionOrder = uniqueIDs(currentOrderIDs)
    }

    private func moveEnabledSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        var enabledIDs = enabledSections.map(\.id)
        enabledIDs.move(fromOffsets: source, toOffset: destination)

        let disabledIDs = sections.map(\.id).filter { !enabledIDs.contains($0) }
        sectionOrder = uniqueIDs(enabledIDs + disabledIDs)
    }

    private func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func row(
        for section: HomeSectionDescriptor,
        isHidden: Bool
    ) -> some View {
        Button {
            setHidden(!isHidden, for: section)
        } label: {
            LabeledContent {
                Image(systemName: isHidden ? "plus.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(isHidden ? .green : .red)
            } label: {
                Label(section.displayTitle, systemImage: section.systemImage)
                    .symbolRenderingMode(.monochrome)
            }
        }
        .foregroundStyle(.primary, .secondary)
    }

    var body: some View {
        Form(systemImage: "rectangle.stack") {
            Section(L10n.enabled) {
                if enabledSections.isEmpty {
                    Text(L10n.none)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(enabledRows) { rowData in
                        row(for: rowData.section, isHidden: rowData.isHidden)
                    }
                    .onMove(perform: moveEnabledSections)
                }
            }

            Section(L10n.disabled) {
                if disabledSections.isEmpty {
                    Text(L10n.none)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(disabledRows) { rowData in
                        row(for: rowData.section, isHidden: rowData.isHidden)
                    }
                }
            }
        }
        .animation(.linear(duration: 0.2), value: sectionOrder)
        .animation(.linear(duration: 0.2), value: hiddenSectionIDs)
        .environment(\.editMode, $editMode)
        .navigationTitle("首页类别")
        .onAppear {
            editMode = .active
        }
        .onFirstAppear {
            guard userSession != nil else { return }
            viewModel.send(.refresh)
        }
    }
}
