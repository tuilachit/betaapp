import Foundation

enum ServiceState: String, Codable, Hashable {
    case configured = "Configured"
    case fixtureMode = "Fixture mode"
    case dormant = "Dormant"
}

struct ServiceStatus: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let state: ServiceState
    let detail: String
}

