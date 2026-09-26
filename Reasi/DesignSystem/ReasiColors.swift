import SwiftUI
import UIKit

struct ReasiColorPalette {
    // Oat neutrals: cream and oat in light, roasted espresso in dark.
    let background = Color(light: 0xF5F0E8, dark: 0x13100E)
    let backgroundElevated = Color(light: 0xFAF6F0, dark: 0x181512)
    let surface = Color(light: 0xFFFCF7, dark: 0x201B18)
    let surfaceHigh = Color(light: 0xEDE5D8, dark: 0x2A2420)
    let glass = Color(light: 0xFFFCF7, dark: 0x241F1B, opacity: 0.82)
    let border = Color(light: 0xDED4C4, dark: 0x362F29)
    let borderStrong = Color(light: 0xC2B5A2, dark: 0x4B423A)
    let text = Color(light: 0x2B211C, dark: 0xF4EEE6)
    let textMuted = Color(light: 0x5B4E45, dark: 0xC7BCAF)
    let muted = Color(light: 0x695C52, dark: 0x998D80)
    let dim = Color(light: 0x6D6056, dark: 0x6E645A)
    let danger = Color(light: 0xB52A31, dark: 0xFF6B6B)
    let warning = Color(light: 0x8A5900, dark: 0xFFD36A)
    let success = Color(light: 0x27633A, dark: 0xD7F4D0)
    let planHighlight = Color(light: 0xF7E6D4, dark: 0x2B2019)

    // Brand: muted red for primary actions and selection, pumpkin for highlights.
    let accent = Color(light: 0xA3473E, dark: 0xD9776A)
    let accentSoft = Color(light: 0xF3E1DB, dark: 0x2E1D1A)
    let onAccent = Color(light: 0xFFFCF7, dark: 0x1F1512)
    let highlight = Color(light: 0xD9772E, dark: 0xE8894A)
    let onHighlight = Color(light: 0x2B211C, dark: 0x1F1512)

    // Photo and camera overlays stay dark in either app appearance.
    let imageBackground = Color(hex: 0x231E1B)
    let onImage = Color(hex: 0xF4EEE6)
    let onImageMuted = Color(hex: 0xC7BCAF)
    let onImageSuccess = Color(hex: 0xD7F4D0)
}

extension Color {
    static let reasi = ReasiColorPalette()

    init(light: UInt, dark: UInt, opacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(opacity)
            )
        })
    }

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
