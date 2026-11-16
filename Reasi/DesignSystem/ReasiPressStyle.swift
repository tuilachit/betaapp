import SwiftUI

struct ReasiPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}

/// The one primary action on a screen: Liquid Glass tinted with Reasi's ink colour, so it
/// reads as solid but still catches light and responds to touch like system controls.
struct ReasiPrimaryButtonStyle: ButtonStyle {
    var allowsMultiline = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ReasiTypography.headline)
            .foregroundStyle(Color.reasi.background)
            .padding(.vertical, allowsMultiline ? ReasiSpacing.s3 : 0)
            .padding(.horizontal, ReasiSpacing.s5)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56, maxHeight: allowsMultiline ? nil : 56)
            .glassEffect(.regular.tint(Color.reasi.text).interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

/// A secondary floating control: plain Liquid Glass in a capsule or circle.
struct ReasiGlassControl<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.glassEffect(.regular.interactive(), in: shape)
    }
}

extension View {
    func reasiGlass<S: Shape>(in shape: S) -> some View {
        modifier(ReasiGlassControl(shape: shape))
    }
}
