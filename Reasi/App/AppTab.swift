import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case plans
    case list
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .plans:
            "Plans"
        case .list:
            "List"
        case .profile:
            "Profile"
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
        case .profile:
            "person.crop.circle"
        }
    }
}

