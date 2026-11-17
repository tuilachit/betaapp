import SwiftUI

struct ReasiPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}

/// The one primary action on a screen: a solid capsule in Reasi's ink colour with the page
/// colour for its label, so it is black on a white page and white on a dark one.
struct ReasiPrimaryButtonStyle: ButtonStyle {
    var allowsMultiline = false
    /// False while the action can't be taken yet (nothing typed, nothing chosen). The button
    /// then turns into a pale grey capsule with muted text, rather than a faded black one.
    /// Leave it true while the button is only busy, so a spinner stays on the solid fill.
    var isAvailable = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ReasiTypography.headline)
            .foregroundStyle(isAvailable ? Color.reasi.background : Color.reasi.muted)
            .padding(.vertical, allowsMultiline ? ReasiSpacing.s3 : 0)
            .padding(.horizontal, ReasiSpacing.s5)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52, maxHeight: allowsMultiline ? nil : 52)
            .background(isAvailable ? Color.reasi.text : Color.reasi.surfaceHigh, in: .capsule)
            // The whole capsule is the tap target and the VoiceOver focus area, not just the words.
            .contentShape([.interaction, .accessibility], .capsule)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
    }
}

/// A secondary action: a quiet grey capsule, the same shape as the primary one.
struct ReasiSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ReasiTypography.bodyMedium)
            .foregroundStyle(Color.reasi.text)
            .padding(.horizontal, ReasiSpacing.s5)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Color.reasi.surface, in: .capsule)
            .contentShape([.interaction, .accessibility], .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ReasiMotion.fast, value: configuration.isPressed)
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

/// A small capsule for a shortcut or a filter. Selected chips invert, like the primary button.
struct ReasiChip: View {
    let title: String
    var symbol: String?
    var trailingSymbol: String?
    var isSelected = false
    /// Stretch to the width on offer, for chips laid out in equal columns.
    var fillsWidth = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: ReasiSpacing.s2) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(.footnote, weight: .medium))
            }
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                // One line at ordinary sizes; at accessibility sizes the label wraps rather
                // than truncating.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.reasi.background : Color.reasi.muted)
            }
        }
        .foregroundStyle(isSelected ? Color.reasi.background : Color.reasi.text)
        .padding(.horizontal, ReasiSpacing.s4)
        .padding(.vertical, ReasiSpacing.s2)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .frame(minHeight: 40)
        .background(isSelected ? Color.reasi.text : Color.reasi.surface, in: .capsule)
        .contentShape([.interaction, .accessibility], .capsule)
    }
}

/// A small muted label above a group, with an optional quiet action on the right.
struct ReasiSectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: ReasiSpacing.s3)
            trailing
        }
    }
}

extension ReasiSectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}
