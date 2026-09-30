import Foundation

// Only platform/UI and transport boundaries are stubbed. The runner compiles
// the checked-in OnboardingStore and OnboardingPreferences unchanged.
@MainActor final class SupabaseService {
    var currentUserId: String?
    var isSignedIn: Bool { currentUserId != nil }
    var authenticatedUserId: String? { currentUserId }
    var remote: [String: OnboardingPreferences] = [:]
    var saves: [(String, OnboardingPreferences)] = []
    var failSaves = false
    var beforeFetchReturn: (() async -> Void)?
    var beforeSaveReturn: (() async -> Void)?
    func fetchOnboardingPreferences() async throws -> OnboardingPreferences? {
        let result = currentUserId.flatMap { remote[$0] }
        await beforeFetchReturn?()
        return result
    }
    func saveOnboardingPreferences(_ preferences: OnboardingPreferences) async throws {
        guard let id = currentUserId, !failSaves else { throw HarnessError.offline }
        saves.append((id, preferences))
        remote[id] = preferences
        await beforeSaveReturn?()
    }
}
enum HarnessError: Error { case offline; case assertion(String) }
@MainActor final class AppState {
    var selectedStore = FixtureStores.topRyde
    func selectStore(_ store: StoreSummary) { selectedStore = store }
}
enum FixtureStores {
    static let topRyde = StoreSummary(id: .topRyde, retailer: "coles", name: "Top Ryde", shortName: "Top Ryde")
    static func store(id: StoreID?) -> StoreSummary? {
        id.map { StoreSummary(id: $0, retailer: "coles", name: $0.rawValue, shortName: $0.rawValue) }
    }
}
enum SpendingCoachTone: String, Codable { case supportive, direct, celebratory }
enum ReasiHaptics {
    static func light() {}; static func selection() {}; static func warning() {}; static func success() {}
}
enum AnalyticsProperty { case string(String), int(Int), bool(Bool), stringArray([String]) }
enum AnalyticsEvent { case onboardingStarted, onboardingPurposeSubmitted, onboardingCompleted }
@MainActor final class AnalyticsService {
    func capture(_ event: AnalyticsEvent, properties: [String: AnalyticsProperty]) {}
}
