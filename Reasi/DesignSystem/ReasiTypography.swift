import SwiftUI

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
    static func font(size: CGFloat, weight: ReasiFontWeight = .regular) -> Font {
        .custom(weight.fontName, size: size, relativeTo: .body)
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

