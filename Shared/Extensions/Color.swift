//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Color {

    static let embyPurple = Color(red: 172 / 255, green: 92 / 255, blue: 195 / 255, opacity: 1)
    static let mediaContentBackground = Color(red: 36 / 255, green: 36 / 255, blue: 44 / 255, opacity: 1)
    static let embyAppBackgroundBase = Color(red: 26 / 255, green: 26 / 255, blue: 32 / 255, opacity: 1)
    static let embyAppBackgroundSurface = Color(red: 34 / 255, green: 34 / 255, blue: 42 / 255, opacity: 1)

    var uiColor: UIColor {
        UIColor(self)
    }

    var overlayColor: Color {
        Color(uiColor: uiColor.overlayColor)
    }

    var mediaDetailBackgroundColor: Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let adjustedSaturation = min(max(saturation * 0.7 + 0.12, 0.14), 0.38)
            let adjustedBrightness = min(max(brightness * 0.34, 0.18), 0.28)

            return Color(uiColor: UIColor(
                hue: hue,
                saturation: adjustedSaturation,
                brightness: adjustedBrightness,
                alpha: 1
            ))
        }

        let components = rgbaComponents
        return Color(
            red: min(max(components.red * 0.34, 0.16), 0.28),
            green: min(max(components.green * 0.34, 0.16), 0.28),
            blue: min(max(components.blue * 0.34, 0.16), 0.28)
        )
    }

    // TODO: Correct and add colors
    #if os(tvOS)
    static let systemFill = Color.white
    static let secondarySystemFill = Color.gray
    static let tertiarySystemFill = Color.black
    static let lightGray = Color(UIColor.lightGray)

    #else
    static let systemBackground = Color.embyAppBackgroundBase
    static let secondarySystemBackground = Color.embyAppBackgroundSurface
    static let tertiarySystemBackground = Color.mediaContentBackground

    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemFill = Color(UIColor.secondarySystemFill)
    static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
    #endif
}

struct EmbyAppBackgroundView: View {

    var body: some View {
        ZStack {
            Color.embyAppBackgroundBase

            LinearGradient(
                stops: [
                    .init(color: Color.embyAppBackgroundSurface.opacity(0.98), location: 0),
                    .init(color: Color.mediaContentBackground.opacity(0.9), location: 0.5),
                    .init(color: Color.embyAppBackgroundBase.opacity(0.96), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

extension UIColor {

    static let embyAppBackground = UIColor(
        red: 26 / 255,
        green: 26 / 255,
        blue: 32 / 255,
        alpha: 1
    )

    static let embyAppBackgroundSurface = UIColor(
        red: 34 / 255,
        green: 34 / 255,
        blue: 42 / 255,
        alpha: 1
    )
}

extension Color {

    struct RGBA {

        enum Component {
            case red
            case green
            case blue
            case alpha
        }

        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat
    }

    var rgbaComponents: RGBA {
        get {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0

            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

            return RGBA(
                red: r,
                green: g,
                blue: b,
                alpha: a
            )
        }
        mutating set {
            self = Color(
                red: newValue.red,
                green: newValue.green,
                blue: newValue.blue,
                opacity: newValue.alpha
            )
        }
    }

    func with(rgba: WritableKeyPath<RGBA, CGFloat>, value: CGFloat) -> Color {
        var components = rgbaComponents
        components[keyPath: rgba] = value
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    init(hex: String) {
        let s = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        let x = UInt64(s, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((x >> 16) & 255) / 255,
            green: Double((x >> 8) & 255) / 255,
            blue: Double(x & 255) / 255,
            opacity: s.count > 6 ? Double((x >> 24) & 255) / 255 : 1
        )
    }

    var hexString: String {
        let components = rgbaComponents
        let r = Int(components.red * 255)
        let g = Int(components.green * 255)
        let b = Int(components.blue * 255)
        let a = Int(components.alpha * 255)

        if a < 255 {
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "%02X%02X%02X", r, g, b)
        }
    }
}
