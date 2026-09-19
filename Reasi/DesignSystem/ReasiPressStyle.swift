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
    var allowsMultiline = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ReasiTypography.headline)
            .foregroundStyle(Color.reasi.background)
            .padding(.vertical, allowsMultiline ? ReasiSpacing.s3 : 0)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64, maxHeight: allowsMultiline ? nil : 64)
            .background(Color.reasi.text, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}
