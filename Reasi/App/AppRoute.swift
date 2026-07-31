import Foundation
import Observation
import SwiftUI

enum AppRoute: Hashable {
    case meal(id: String)
    case section(label: String)
}

@MainActor
@Observable
final class RouterPath {
    var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path = []
    }
}

