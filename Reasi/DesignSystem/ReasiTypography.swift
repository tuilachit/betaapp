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
/// Two families, both Apple's: New York (serif) for display — screen titles, section
/// headings, dish names and big money figures — and San Francisco for everything else.
/// Every font here is one of the system's built-in text styles, so it follows Dynamic Type
/// and Bold Text and matches the text inside system controls.
enum ReasiTypography {
    /// Flip to `.default` to set display text in San Francisco instead of New York.
    static let displayDesign: Font.Design = .serif

    /// Native navigation bars keep their Liquid Glass and scroll behaviour; only the title face changes.
    @MainActor
    static func applyNavigationBarFonts() {
        let bar = UINavigationBar.appearance()
        // Large titles are display text. Small inline titles stay in the system face,
        // like the labels of the controls beside them.
        bar.largeTitleTextAttributes = [.font: displayUIFont(.largeTitle, weight: .semibold)]
    }

    private static func displayUIFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        // The size at the default text setting; UIFontMetrics then scales it once for Dynamic Type.
        let baseSize: CGFloat = style == .largeTitle ? 34 : 17
        let weighted = UIFont.systemFont(ofSize: baseSize, weight: weight)
        let design: UIFontDescriptor.SystemDesign = displayDesign == .serif ? .serif : .default
        let descriptor = weighted.fontDescriptor.withDesign(design) ?? weighted.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: baseSize))
    }

    /// Display text: New York, in a built-in text style.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: displayDesign, weight: weight)
    }

    /// A font near `size`, snapped to the closest built-in text style. Sizes of 20 and up are
    /// display text and use New York; smaller sizes are interface text in San Francisco.
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
            display(.title2, weight: .semibold)
        case 20..<21:
            display(.title3, weight: .semibold)
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
    static let title2 = display(.title2, weight: .semibold)

    // Interface
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.callout)
    static let bodyMedium = Font.system(.callout, weight: .medium)
    /// Secondary text. Regular weight in a muted colour, rather than small and heavy.
    static let callout = Font.system(.subheadline)
    static let caption = Font.system(.caption, weight: .medium)
    static let navLabel = Font.system(.caption2, weight: .semibold)
}
