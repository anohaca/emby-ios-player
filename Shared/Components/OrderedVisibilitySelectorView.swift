//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct OrderedVisibilitySelectorView<Element: Displayable & Hashable>: View {

    @StateObject
    private var order: BindingBox<[Element]>
    @StateObject
    private var hidden: BindingBox<[Element]>
    @State
    private var editMode: EditMode = .active

    private let data: [Element]
    private let systemImage: String

    private struct Row: Identifiable {
        let element: Element
        let isHidden: Bool

        var id: String {
            "\(isHidden ? "disabled" : "enabled"):\(element)"
        }
    }

    init(
        systemImage: String = "filemenu.and.selection",
        order: Binding<[Element]>,
        hidden: Binding<[Element]>,
        sources: [Element]
    ) {
        self._order = StateObject(wrappedValue: BindingBox(source: order))
        self._hidden = StateObject(wrappedValue: BindingBox(source: hidden))
        self.data = sources
        self.systemImage = systemImage
    }

    private var normalizedOrder: [Element] {
        order.value.filter { data.contains($0) } + data.filter { !order.value.contains($0) }
    }

    private var hiddenSet: Set<Element> {
        Set(hidden.value)
    }

    private var enabledSelection: [Element] {
        normalizedOrder.filter { !hiddenSet.contains($0) }
    }

    private var disabledSelection: [Element] {
        normalizedOrder.filter { hiddenSet.contains($0) }
    }

    private var enabledRows: [Row] {
        enabledSelection.map { Row(element: $0, isHidden: false) }
    }

    private var disabledRows: [Row] {
        disabledSelection.map { Row(element: $0, isHidden: true) }
    }

    private func persistOrder(_ newOrder: [Element]) {
        order.value = newOrder
        hidden.value = hidden.value.filter { newOrder.contains($0) }
    }

    private func setHidden(_ isHidden: Bool, for element: Element) {
        var hiddenItems = hidden.value

        if isHidden {
            hiddenItems.append(element)
        } else {
            hiddenItems.removeAll(equalTo: element)
        }

        hidden.value = unique(hiddenItems)
        persistOrder(normalizedOrder)
        UIDevice.impact(.light)
    }

    private func moveEnabledSelection(fromOffsets source: IndexSet, toOffset destination: Int) {
        var enabled = enabledSelection
        enabled.move(fromOffsets: source, toOffset: destination)
        persistOrder(enabled + disabledSelection)
    }

    private func unique(_ elements: [Element]) -> [Element] {
        var seen = Set<Element>()
        return elements.filter { seen.insert($0).inserted }
    }

    private func row(
        for element: Element,
        isHidden: Bool
    ) -> some View {
        Button {
            setHidden(!isHidden, for: element)
        } label: {
            LabeledContent {
                Image(systemName: isHidden ? "plus.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(isHidden ? .green : .red)
            } label: {
                if let imageable = element as? SystemImageable {
                    Label(element.displayTitle, systemImage: imageable.systemImage)
                        .symbolRenderingMode(.monochrome)
                } else {
                    Text(element.displayTitle)
                }
            }
        }
        .foregroundStyle(.primary, .secondary)
    }

    var body: some View {
        Form(systemImage: systemImage) {
            Section(L10n.enabled) {
                if enabledSelection.isEmpty {
                    Text(L10n.none)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(enabledRows) { rowData in
                        row(for: rowData.element, isHidden: rowData.isHidden)
                    }
                    .onMove(perform: moveEnabledSelection)
                }
            }

            Section(L10n.disabled) {
                if disabledSelection.isEmpty {
                    Text(L10n.none)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(disabledRows) { rowData in
                        row(for: rowData.element, isHidden: rowData.isHidden)
                    }
                }
            }
        }
        .animation(.linear(duration: 0.2), value: order.value)
        .animation(.linear(duration: 0.2), value: hidden.value)
        .environment(\.editMode, $editMode)
        .onAppear {
            editMode = .active
            persistOrder(normalizedOrder)
        }
    }
}
