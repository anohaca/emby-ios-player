//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct ScrollViewOffsetModifier: ViewModifier {

    @StateObject
    private var scrollViewDelegate: ScrollViewDelegate

    init(scrollViewOffset: Binding<CGFloat>) {
        self._scrollViewDelegate = StateObject(wrappedValue: ScrollViewDelegate(scrollViewOffset: scrollViewOffset))
    }

    func body(content: Content) -> some View {
        content.introspect(
            .scrollView,
            on: .iOS(.v15...),
            .tvOS(.v15...)
        ) { scrollView in
            scrollView.delegate = scrollViewDelegate
        }
    }

    private class ScrollViewDelegate: NSObject, ObservableObject, UIScrollViewDelegate {

        let scrollViewOffset: Binding<CGFloat>

        init(scrollViewOffset: Binding<CGFloat>) {
            self.scrollViewOffset = scrollViewOffset
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollViewOffset.wrappedValue = scrollView.contentOffset.y
        }
    }
}

struct ScrollViewOffsetCallbackModifier: ViewModifier {

    @StateObject
    private var scrollViewObserver = ScrollViewCallbackObserver()
    private let onChange: (CGFloat) -> Void

    init(onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
    }

    func body(content: Content) -> some View {
        content.introspect(
            .scrollView,
            on: .iOS(.v15...),
            .tvOS(.v15...),
            scope: .receiver
        ) { scrollView in
            scrollViewObserver.attach(to: scrollView, onChange: onChange)
        }
    }
}

struct ClearScrollViewBackgroundModifier: ViewModifier {

    func body(content: Content) -> some View {
        content.introspect(
            .scrollView,
            on: .iOS(.v15...),
            .tvOS(.v15...),
            scope: .receiver
        ) { scrollView in
            scrollView.backgroundColor = .clear
        }
    }
}

private final class ScrollViewCallbackObserver: NSObject, ObservableObject {

    var onChange: ((CGFloat) -> Void)?
    private weak var scrollView: UIScrollView?

    func attach(to scrollView: UIScrollView, onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange

        guard self.scrollView !== scrollView else { return }

        if let previousScrollView = self.scrollView {
            previousScrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), context: &observationContext)
        }

        self.scrollView = scrollView
        scrollView.addObserver(
            self,
            forKeyPath: #keyPath(UIScrollView.contentOffset),
            options: [.initial, .new],
            context: &observationContext
        )
    }

    deinit {
        scrollView?.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), context: &observationContext)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &observationContext,
              keyPath == #keyPath(UIScrollView.contentOffset),
              let scrollView = object as? UIScrollView
        else { return }

        // Report the distance from the scroll view's actual top rather than
        // the raw contentOffset. UIKit starts a scroll view at
        // `-adjustedContentInset.top`, and that value can change when the
        // navigation bar/layout settles. Using the normalized distance keeps
        // the top position stable so chrome can hide and reappear correctly.
        let distanceFromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        onChange?(max(0, distanceFromTop))
    }

    private var observationContext = 0
}
