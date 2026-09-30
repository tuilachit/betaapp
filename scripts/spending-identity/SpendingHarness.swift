import Foundation

@main struct SpendingIdentityHarness {
    static let payload = """
    {"period":"week","startDate":"2026-09-01","endDateExclusive":"2026-09-08","currency":"AUD","completedSpendAud":99,"trackedItemSpendAud":99,"checkoutDifferenceAud":0,"priceCoverage":1,"checkedItems":1,"pricedCheckedItems":1,"plannedSpendAud":99,"addedSpendAud":0,"categories":[],"trend":[],"recentTrips":[],"insightCards":[],"timezone":"Australia/Sydney","coachTone":"supportive"}
    """
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ pass: Bool, _ name: String) { print("\(pass ? "PASS" : "FAIL") \(name)"); if !pass { failures += 1 } }
        let service = SupabaseService()
        service.dashboard = try JSONDecoder().decode(SpendingDashboard.self, from: Data(payload.utf8))
        let first = SpendingStore()
        first.activate(userId: UUID().uuidString)
        service.currentUserId = UUID().uuidString
        await first.refresh(supabase: service)
        check(first.dashboard == nil && service.fetchCount == 0, "reject B token while cache belongs to A")
        let second = SpendingStore()
        let account = UUID().uuidString
        service.currentUserId = account
        second.activate(userId: account)
        service.beforeReturn = { service.currentUserId = UUID().uuidString }
        await second.refresh(supabase: service)
        check(second.dashboard == nil, "drop dashboard after auth identity changes")
        let detailJSON = """
        {"trip":{"id":"trip","shoppingListId":"list","storeId":"top_ryde","storeName":"Top Ryde","completedAt":"2026-09-01","knownBasketTotalAud":99,"checkedItems":1,"pricedCheckedItems":1,"trackedTotalAud":99,"effectiveTotalAud":99,"checkoutDifferenceAud":0,"priceCoverage":1,"weeklySpendAud":99},"categories":[],"plannedSpendAud":99,"addedSpendAud":0,"insightStatus":"stale","insightCards":[],"items":[]}
        """
        service.detail = try JSONDecoder().decode(SpendingTripDetail.self, from: Data(detailJSON.utf8))
        service.currentUserId = account
        service.beforeReturn = nil
        service.fetchCount = 0
        await second.loadTrip(id: "trip", supabase: service)
        check(service.fetchCount == 1, "stale fallback is terminal until explicit retry")
        if failures > 0 { exit(1) }
    }
}
