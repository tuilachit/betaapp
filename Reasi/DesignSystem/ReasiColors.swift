import SwiftUI

struct ReasiColorPalette {
    let background = Color(hex: 0x09090A)
    let backgroundElevated = Color(hex: 0x0D0D0F)
    let surface = Color(hex: 0x171719)
    let surfaceHigh = Color(hex: 0x202023)
    let glass = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255, opacity: 0.82)
    let border = Color(hex: 0x29292D)
    let borderStrong = Color(hex: 0x3D3D43)
    let text = Color(hex: 0xF4F4F5)
    let textMuted = Color(hex: 0xB8B8BF)
    let muted = Color(hex: 0x85858E)
    let dim = Color(hex: 0x5E5E66)
    let danger = Color(hex: 0xFF6B6B)
    let warning = Color(hex: 0xFFD36A)
    let success = Color(hex: 0xD7F4D0)
}

extension Color {
    static let reasi = ReasiColorPalette()

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
