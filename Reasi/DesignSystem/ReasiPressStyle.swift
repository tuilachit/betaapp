import SwiftUI

struct ReasiPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}

struct ReasiPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ReasiTypography.headline)
            .foregroundStyle(Color.reasi.background)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Color.reasi.text, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}

