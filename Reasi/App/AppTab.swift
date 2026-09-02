import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case plans
    case list
    case spend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .plans:
            "Plans"
        case .list:
            "List"
        case .spend:
            "Spend"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            "house.fill"
        case .plans:
            "fork.knife"
        case .list:
            "checklist"
        case .spend:
            "chart.bar.fill"
        }
    }
}
