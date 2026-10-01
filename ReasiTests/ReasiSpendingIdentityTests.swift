import XCTest
@testable import Reasi

@MainActor
final class ReasiSpendingIdentityTests: XCTestCase {
    func testStaleInsightsAreTerminalAndRetryableWithoutBeingPending() {
        XCTAssertTrue(SpendingInsightLoadState.canRetry("stale"))
        XCTAssertTrue(SpendingInsightLoadState.isTerminal("stale"))
        XCTAssertFalse(SpendingInsightLoadState.isPending("stale"))
        XCTAssertTrue(SpendingInsightLoadState.isPending("in_progress"))
        XCTAssertFalse(SpendingInsightLoadState.canRetry("in_progress"))
        XCTAssertFalse(SpendingInsightLoadState.isTerminal("in_progress"))
    }

    private func cache() -> SpendingLocalCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return SpendingLocalCache(directoryURL: directory)
    }

    func testRefreshRejectsNewAccountTokenBeforeCacheRebind() async throws {
        let cache = cache()
        let store = SpendingStore(cache: cache)
        store.activate(userId: "A")
        let remote = SpendingIdentityRemote()
        remote.authenticatedUserId = "B"
        await store.refresh(supabase: remote)
        XCTAssertEqual(remote.fetchCount, 0)
        XCTAssertNil(store.dashboard)
        XCTAssertNil(cache.loadDashboard(userId: "A", period: .week))
    }

    func testRefreshDropsResponseAfterIdentityChangeEvenBeforeCacheRebind() async throws {
        let cache = cache()
        let store = SpendingStore(cache: cache)
        store.activate(userId: "A")
        let remote = SpendingIdentityRemote()
        remote.authenticatedUserId = "A"
        remote.beforeReturn = { remote.authenticatedUserId = "B" }
        await store.refresh(supabase: remote)
        XCTAssertNil(store.dashboard)
        XCTAssertNil(cache.loadDashboard(userId: "A", period: .week))
    }

    func testRefreshRejectsOldSessionEpochEvenWhenUUIDReturnsToSameValue() async {
        let store = SpendingStore(cache: cache())
        store.activate(userId: "A")
        let remote = SpendingIdentityRemote()
        remote.authenticatedUserId = "A"
        remote.beforeReturn = { remote.authIdentityRevision += 2 }
        await store.refresh(supabase: remote)
        XCTAssertNil(store.dashboard)
    }

    func testCurrentIdentityResponseIsPersistedOnlyToItsOwnCache() async throws {
        let cache = cache()
        let store = SpendingStore(cache: cache)
        store.activate(userId: "B")
        let remote = SpendingIdentityRemote()
        remote.authenticatedUserId = "B"
        await store.refresh(supabase: remote)
        XCTAssertEqual(store.dashboard?.completedSpendAud, 99)
        XCTAssertEqual(cache.loadDashboard(userId: "B", period: .week)?.completedSpendAud, 99)
        XCTAssertNil(cache.loadDashboard(userId: "A", period: .week))
    }

    func testTripFailureFromPreviousIdentityDoesNotSetNewAccountsMessage() async {
        let store = SpendingStore(cache: cache())
        store.activate(userId: "A")
        let remote = SpendingIdentityRemote()
        remote.authenticatedUserId = "A"
        remote.beforeReturn = {
            remote.authenticatedUserId = "B"
            store.activate(userId: "B")
        }
        await store.loadTrip(id: "trip-A", supabase: remote, pollForInsights: false)
        XCTAssertNil(store.selectedTrip)
        XCTAssertNil(store.tripMessage)
    }
}

@MainActor
private final class SpendingIdentityRemote: SpendingService {
    var authenticatedUserId: String?
    var authIdentityRevision = 0
    var isSignedIn: Bool { authenticatedUserId != nil }
    var fetchCount = 0
    var beforeReturn: (() async -> Void)?

    func fetchSpendingDashboard(period: SpendingPeriod, anchorDate: String?) async throws -> SpendingDashboard {
        fetchCount += 1
        let json = """
        {"period":"week","startDate":"2026-09-01","endDateExclusive":"2026-09-08","currency":"AUD","completedSpendAud":99,"trackedItemSpendAud":99,"checkoutDifferenceAud":0,"priceCoverage":1,"checkedItems":1,"pricedCheckedItems":1,"plannedSpendAud":99,"addedSpendAud":0,"categories":[],"trend":[],"recentTrips":[],"insightCards":[],"timezone":"Australia/Sydney","coachTone":"supportive"}
        """
        await beforeReturn?()
        return try JSONDecoder().decode(SpendingDashboard.self, from: Data(json.utf8))
    }

    func fetchSpendingTripDetail(tripId: String) async throws -> SpendingTripDetail {
        await beforeReturn?()
        throw URLError(.notConnectedToInternet)
    }

    func correctShoppingTotal(tripId: String, totalAud: Double) async throws -> SpendingTotalCorrection {
        throw URLError(.notConnectedToInternet)
    }

    func retrySpendingInsight(tripId: String) async throws { throw URLError(.notConnectedToInternet) }
    func userFacingMessage(for error: Error, fallback: String) -> String { fallback }
}
