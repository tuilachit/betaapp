#if CORE_LOOP_HOST_TESTS
import Foundation

// Only transport/UI boundaries are doubled. Store, models, cache and fixtures are real.
@MainActor final class SupabaseService {
    var currentUserId: String? = UUID().uuidString
    var isSignedIn: Bool { currentUserId != nil }
    var status = Status()
    struct Status { var state = State.configured }
    enum State { case configured }
    var add: (String) async throws -> String? = { _ in "persisted-item" }
    var finish: (ShoppingList) async throws -> ShoppingTripSummary = { list in
        ShoppingTripSummary(tripId: "trip", shoppingListId: list.id, storeId: list.storeId,
            storeName: list.storeName, totalItems: 1, checkedItems: 1, pricedItems: 1,
            pricedCheckedItems: 1, knownPlannedTotalAud: 5, knownBasketTotalAud: 5,
            completedAt: "2026-09-30T00:00:00Z", alreadyCompleted: false)
    }
    var start: () async throws -> WeekPlanGenerationStartResult = { .fixture(FixtureWeekPlan.current) }
    var regroup: (String, StoreID) async throws -> WeekPlan = { _, _ in FixtureWeekPlan.current }
    var fetch: (String) async throws -> WeekPlan? = { _ in nil }
    var recent: () async throws -> [RecentPlanSummary] = { [] }
    var delete: (String, String) async throws -> Void = { _, _ in }
    var check: (String, String, Bool) async throws -> Void = { _, _, _ in }
    var select: () async throws -> Bool = { true }
    var deleted: [String] = []
    var cancelled: [String] = []
    var inserted: [String] = []
    func searchProducts(query: String, storeId: StoreID, limit: Int) async throws -> [ProductCandidate] { [] }
    func selectProduct(_ candidate: ProductCandidate, for item: ShoppingListItem, shoppingListId: String,
        sectionLabel: String, sectionSortKey: Int, sectionType: ShoppingSectionType,
        actualPriceAud: Double?, productSnapshot: ProductSnapshot?, onlyIfUnselected: Bool = false) async throws -> Bool { try await select() }
    func saveSelectedStore(_ store: StoreID) async throws {}
    func regroupShoppingList(shoppingListId: String, from: StoreID, to: StoreID) async throws -> WeekPlan {
        try await regroup(shoppingListId, to)
    }
    func fetchWeekPlan(id: String) async throws -> WeekPlan? { try await fetch(id) }
    func fetchLatestWeekPlan() async throws -> WeekPlan? { nil }
    func fetchLatestUnfinishedGeneration() async throws -> WeekPlanGenerationRequest? { nil }
    func startWeekPlanGeneration(input: GenerateWeekPlanInput) async throws -> WeekPlanGenerationStartResult { try await start() }
    func generationStatus(requestId: String) async throws -> WeekPlanGenerationRequest { throw ReasiServiceError.offline }
    func cancelWeekPlanGeneration(requestId: String) async throws -> WeekPlanGenerationRequest {
        cancelled.append(requestId)
        return request(requestId, status: .cancelRequested, stage: .cancelled)
    }
    func updateShoppingListItemChecked(itemId: String, shoppingListId: String, checked: Bool) async throws {
        try await check(itemId, shoppingListId, checked)
    }
    func addImportedCandidateToShoppingList(shoppingListId: String, candidate: ProductCandidate,
        quantity: String, sortOrder: Int, idempotencyKey: UUID, origin: String?) async throws -> String? {
        inserted.append(shoppingListId)
        return try await add(shoppingListId)
    }
    func deleteShoppingListItem(itemId: String, shoppingListId: String) async throws {
        try await delete(itemId, shoppingListId)
        deleted.append("\(shoppingListId)/\(itemId)")
    }
    func finishShopping(_ list: ShoppingList, checkedItemIDs: Set<String>) async throws -> ShoppingTripSummary { try await finish(list) }
    func fetchRecentPlans() async throws -> [RecentPlanSummary] { try await recent() }
    func userFacingMessage(for error: Error, fallback: String) -> String { fallback }
}

enum ReasiServiceError: Error { case offline, invalidResponse, reasiProRequired, requestFailed(String) }
@MainActor final class NetworkMonitor { var isConnected = true }
@MainActor final class AppState {
    var selectedStore = FixtureStores.store(id: .topRyde)!
    var planBuilder = Builder()
    struct Builder { func discard() {} }
    func selectStore(_ store: StoreSummary) { selectedStore = store }
    func showPlan() {}
    func showShoppingList() {}
}
enum ReasiHaptics {
    static func light() {}
    static func success() {}
    static func warning() {}
    static func selection() {}
}
enum AnalyticsProperty { case string(String), bool(Bool), int(Int), double(Double) }
enum AnalyticsEvent {
    case storeSelected, planGenerationStarted, shoppingListCreated, shoppingListViewed,
         shoppingItemChecked, shoppingItemDeleted, productCandidateAdded, weekPlanViewed,
         shoppingFinishStarted, shoppingFinished, shoppingFinishFailed, shoppingListProgress
}
@MainActor final class AnalyticsService {
    func capture(_ event: AnalyticsEvent, properties: [String: AnalyticsProperty]) {}
    func flush() {}
}

func request(_ id: String, status: GenerationRequestStatus = .inProgress,
             stage: GenerationRequestStage = .preparing) -> WeekPlanGenerationRequest {
    WeekPlanGenerationRequest(requestId: id, status: status, stage: stage, storeId: .topRyde,
        weekStart: nil, mealPlanId: nil, shoppingListId: nil, errorCode: nil, message: nil,
        expiresAt: nil, accessMode: nil, createdAt: nil)
}
#endif
