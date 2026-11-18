import SwiftUI
import UIKit

enum ReasiFontWeight {
    case regular
    case medium
    case semibold
    case bold

    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Reasi's type, per `docs/design-playbook.md`.
///
/// One family: San Francisco, in the system's built-in text styles, so every font follows
/// Dynamic Type and Bold Text and matches the text inside system controls. Display text —
/// screen titles, section headings, dish names and big money figures — is set apart by size
/// and a medium weight, not by a second typeface.
enum ReasiTypography {
    /// `.default` is San Francisco. `.serif` would set display text in New York instead.
    static let displayDesign: Font.Design = .default

    /// Native navigation bars keep their Liquid Glass and scroll behaviour; only the title face changes.
    @MainActor
    static func applyNavigationBarFonts() {
        let bar = UINavigationBar.appearance()
        // Large titles are display text, in the same medium weight as the rest of it.
        // Small inline titles keep the system's own style.
        bar.largeTitleTextAttributes = [.font: displayUIFont(.largeTitle, weight: .medium)]
    }

    private static func displayUIFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        // The size at the default text setting; UIFontMetrics then scales it once for Dynamic Type.
        let baseSize: CGFloat = style == .largeTitle ? 34 : 17
        let weighted = UIFont.systemFont(ofSize: baseSize, weight: weight)
        let design: UIFontDescriptor.SystemDesign = displayDesign == .serif ? .serif : .default
        let descriptor = weighted.fontDescriptor.withDesign(design) ?? weighted.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: baseSize))
    }

    /// Display text: a built-in text style in the display design, medium weight.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: displayDesign, weight: weight)
    }

    /// A font near `size`, snapped to the closest built-in text style. Sizes of 20 and up are
    /// display text in a medium weight; smaller sizes are interface text in the weight asked for.
    /// `relativeTo` is accepted for source compatibility; the chosen style already scales.
    static func font(size: CGFloat, weight: ReasiFontWeight = .regular, relativeTo _: Font.TextStyle = .body) -> Font {
        switch size {
        case 40...:
            // Poster figures, such as the budget amount in onboarding. Already far above any
            // reading size, so they stay fixed rather than growing off the screen.
            .system(size: size, weight: .medium, design: displayDesign)
        case 33..<40:
            display(.largeTitle)
        case 26..<33:
            display(.title)
        case 21..<26:
            display(.title2)
        case 20..<21:
            display(.title3)
        case 17..<20:
            .system(.body, weight: weight.system)
        case 16..<17:
            .system(.callout, weight: weight.system)
        case 14..<16:
            .system(.subheadline, weight: weight.system)
        case 13..<14:
            .system(.footnote, weight: weight.system)
        case 12..<13:
            .system(.caption, weight: weight.system)
        default:
            .system(.caption2, weight: weight.system)
        }
    }

    // Display
    static let largeTitle = display(.largeTitle)
    static let title = display(.title)
    static let title2 = display(.title2)

    // Interface
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.callout)
    static let bodyMedium = Font.system(.callout, weight: .medium)
    /// Secondary text. Regular weight in a muted colour, rather than small and heavy.
    static let callout = Font.system(.subheadline)
    static let caption = Font.system(.caption, weight: .medium)
    static let navLabel = Font.system(.caption2, weight: .semibold)
}
