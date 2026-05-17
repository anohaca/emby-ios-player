//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct BottomEdgeGradientModifier: ViewModifier {

    let bottomColor: Color

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .overlay {
                    bottomColor
                        .maskLinearGradient {
                            (location: 0.52, opacity: 0)
                            (location: 0.68, opacity: 0.4)
                            (location: 0.84, opacity: 0.82)
                            (location: 1, opacity: 1)
                        }
                }

            bottomColor
        }
    }
}

struct TopEdgeGradientModifier: ViewModifier {

    let topColor: Color
    let bottomColor: Color

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: topColor.opacity(0.9), location: 0),
                        .init(color: topColor.opacity(0.62), location: 0.3),
                        .init(color: bottomColor.opacity(0.92), location: 0.76),
                        .init(color: bottomColor.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .allowsHitTesting(false)
            }
    }
}
