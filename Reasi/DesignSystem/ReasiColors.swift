import SwiftUI
import UIKit

struct ReasiColorPalette {
    let background = Color(light: 0xF6F6F8, dark: 0x09090A)
    let backgroundElevated = Color(light: 0xFBFBFC, dark: 0x0D0D0F)
    let surface = Color(light: 0xFFFFFF, dark: 0x171719)
    let surfaceHigh = Color(light: 0xEDEDF1, dark: 0x202023)
    let glass = Color(light: 0xFFFFFF, dark: 0x1C1C1E, opacity: 0.82)
    let border = Color(light: 0xD7D7DE, dark: 0x29292D)
    let borderStrong = Color(light: 0xB4B4BE, dark: 0x3D3D43)
    let text = Color(light: 0x19191D, dark: 0xF4F4F5)
    let textMuted = Color(light: 0x51515B, dark: 0xB8B8BF)
    let muted = Color(light: 0x62626D, dark: 0x85858E)
    let dim = Color(light: 0x666670, dark: 0x5E5E66)
    let danger = Color(light: 0xB52A31, dark: 0xFF6B6B)
    let warning = Color(light: 0x8A5900, dark: 0xFFD36A)
    let success = Color(light: 0x27633A, dark: 0xD7F4D0)
    let planHighlight = Color(light: 0xE7F0E3, dark: 0x20251E)

    // Photo and camera overlays stay dark in either app appearance.
    let imageBackground = Color(hex: 0x202023)
    let onImage = Color(hex: 0xF4F4F5)
    let onImageMuted = Color(hex: 0xB8B8BF)
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
