import SwiftUI
import UIKit

enum ReasiFontWeight {
    case regular
    case medium
    case semibold
    case bold

    var fontName: String {
        switch self {
        case .regular:
            "Inter-Regular"
        case .medium:
            "Inter-Medium"
        case .semibold:
            "Inter-SemiBold"
        case .bold:
            "Inter-Bold"
        }
    }
}

enum ReasiTypography {
    /// Native navigation bars keep their Liquid Glass and scroll behaviour; only the title font changes to Inter.
    @MainActor
    static func applyNavigationBarFonts() {
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: ReasiFontWeight.bold.fontName, size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: ReasiFontWeight.semibold.fontName, size: 17) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }

    static func font(size: CGFloat, weight: ReasiFontWeight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: textStyle)
    }

    static let largeTitle = font(size: 42, weight: .semibold)
    static let title = font(size: 34, weight: .semibold)
    static let title2 = font(size: 24, weight: .semibold)
    static let headline = font(size: 17, weight: .semibold)
    static let body = font(size: 16, weight: .regular)
    static let bodyMedium = font(size: 16, weight: .medium)
    static let callout = font(size: 14, weight: .medium)
    static let caption = font(size: 12, weight: .semibold)
    static let navLabel = font(size: 10.5, weight: .semibold)
}
