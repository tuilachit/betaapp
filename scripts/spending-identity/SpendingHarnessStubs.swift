import Foundation

@MainActor final class SupabaseService {
    var currentUserId: String?
    var authIdentityRevision = 0
    var authenticatedUserId: String? { currentUserId }
    var isSignedIn: Bool { currentUserId != nil }
    var dashboard: SpendingDashboard!
    var detail: SpendingTripDetail!
    var fetchCount = 0
    var beforeReturn: (() async -> Void)?
    func fetchSpendingDashboard(period: SpendingPeriod, anchorDate: String?) async throws -> SpendingDashboard {
        fetchCount += 1
        let value = dashboard!
        await beforeReturn?()
        return value
    }
    func fetchSpendingTripDetail(tripId: String) async throws -> SpendingTripDetail {
        fetchCount += 1
        let value = detail!
        await beforeReturn?()
        return value
    }
    func correctShoppingTotal(tripId: String, totalAud: Double) async throws -> SpendingTotalCorrection {
        fatalError("Not used by host regression")
    }
    func retrySpendingInsight(tripId: String) async throws {}
    func userFacingMessage(for error: Error, fallback: String) -> String { fallback }
}
enum AnalyticsProperty { case string(String) }
enum AnalyticsEvent { case spendingPeriodChanged, spendingTotalCorrected }
@MainActor final class AnalyticsService {
    func capture(_ event: AnalyticsEvent, properties: [String: AnalyticsProperty]) {}
}
enum ReasiHaptics { static func success() {}; static func warning() {} }
