import Foundation
import XCTest
#if !CORE_LOOP_HOST_TESTS
@testable import Reasi
#endif

@MainActor
final class CoreLoopReliabilityTests: XCTestCase {
    func testAssistantQuantityChangeInvalidatesEstimatedPrice() {
        let core = CoreLoopStore(plan: makePlan("A"))
        core.applyAssistantMutations([mutation(quantity: "1 kg")])
        let item = core.allShoppingItems[0]
        XCTAssertEqual(item.quantity, "1 kg")
        XCTAssertEqual(item.id, "rice")
        XCTAssertTrue(item.checked)
        XCTAssertNil(item.product?.priceAud)
        XCTAssertNil(item.product?.purchaseQuantity)
        XCTAssertNil(item.importedCandidate)
    }

    func testAssistantCheckOnlyPreservesPrice() {
        let core = CoreLoopStore(plan: makePlan("A"))
        core.applyAssistantMutations([mutation(quantity: nil)])
        XCTAssertEqual(core.allShoppingItems[0].product?.priceAud, 5)
    }

    #if CORE_LOOP_HOST_TESTS
    func testHistoryResponseAfterAccountSwitchCannotPublishOrClearNewLoadingState() async throws {
        let (core, service) = setup()
        let a = Gate<[RecentPlanSummary]>()
        let b = Gate<[RecentPlanSummary]>()
        service.recent = { await a.wait() }
        let refreshingA = Task { await core.refreshRecentPlans(supabase: service) }
        try await a.started()
        service.currentUserId = UUID().uuidString
        core.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        XCTAssertFalse(core.isLoadingRecentPlans, "Activation must reset A's loading state")
        service.recent = { await b.wait() }
        let refreshingB = Task { await core.refreshRecentPlans(supabase: service) }
        try await b.started()
        a.resume([RecentPlanSummary(id: "private-A", name: "A history", kind: .week, storeId: .topRyde, createdAt: nil)])
        try await completeWithinTimeout(refreshingA)
        XCTAssertTrue(core.recentPlans.isEmpty)
        XCTAssertTrue(core.isLoadingRecentPlans, "A's defer must not clear B's loading state")
        b.resume([RecentPlanSummary(id: "private-B", name: "B history", kind: .week, storeId: .topRyde, createdAt: nil)])
        try await completeWithinTimeout(refreshingB)
        XCTAssertEqual(core.recentPlans.map(\.id), ["private-B"])
        XCTAssertFalse(core.isLoadingRecentPlans)
    }

    func testDelayedRestoreCannotUndoSuccessfulRetailerSwitch() async throws {
        let (core, service) = setup()
        let sourceStore = FixtureStores.store(id: .topRyde)!
        let target = FixtureStores.store(id: .woolworthsRhodes)!
        core.activateUser(nil, selectedStore: sourceStore)
        core.activateUser(service.currentUserId, selectedStore: sourceStore)
        let old = core.plan
        let gate = Gate<WeekPlan?>()
        service.fetch = { _ in await gate.wait() }
        let restoring = Task { await core.restoreLatestPlan(supabase: service, selectedStore: sourceStore) }
        try await gate.started()
        service.regroup = { _, _ in
            WeekPlan(id: old.id, source: old.source, storeId: target.id, storeName: target.name,
                weekLabel: old.weekLabel, planningNotes: old.planningNotes, meals: old.meals,
                shoppingList: ShoppingList(id: old.shoppingList.id, storeId: target.id,
                    storeName: target.name, sections: old.shoppingList.sections))
        }
        core.requestStoreSwitch(to: target, appState: AppState(), supabase: service, analytics: AnalyticsService())
        try await waitUntil { core.plan.storeId == target.id && !core.isSwitchingStore }
        gate.resume(old)
        try await completeWithinTimeout(restoring)
        XCTAssertEqual(core.plan.storeId, target.id)
        XCTAssertEqual(core.plan.shoppingList.storeId, target.id)
        XCTAssertNil(core.allShoppingItems[0].product)
        XCTAssertFalse(core.isRestoringPlan)
        let relaunched = CoreLoopStore()
        relaunched.activateUser(service.currentUserId, selectedStore: target)
        XCTAssertEqual(relaunched.plan.storeId, target.id)
        XCTAssertNil(relaunched.allShoppingItems[0].product)
    }

    func testLostImportResponseRestoresLocalCheckUsingRemoteClientIdentity() async throws {
        let (core, service) = setup()
        let key = UUID().uuidString.lowercased()
        let remoteID = "committed-import"
        var remote = makePlan("A")
        service.add = { _ in
            remote.shoppingList.sections[0].items.append(self.committedImport(id: remoteID, clientID: key))
            throw ReasiServiceError.offline
        }
        try await completeWithinTimeout(Task {
            _ = await core.addImportedCandidate(candidate(), idempotencyKey: key,
                supabase: service, analytics: AnalyticsService())
        })
        let local = try XCTUnwrap(core.allShoppingItems.first { $0.clientId == key })
        core.toggleItem(local, supabase: service, analytics: AnalyticsService())
        let restored = CoreLoopStore()
        restored.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        service.fetch = { _ in remote }
        service.add = { _ in remoteID }
        var checks: [String] = []
        service.check = { item, list, checked in
            checks.append("\(list)/\(item)/\(checked)")
            if let index = remote.shoppingList.sections[0].items.firstIndex(where: { $0.id == item }) {
                remote.shoppingList.sections[0].items[index].checked = checked
            }
        }
        try await completeWithinTimeout(Task {
            await restored.restoreLatestPlan(supabase: service, selectedStore: FixtureStores.store(id: .topRyde)!)
            await restored.flushPendingShoppingChanges(supabase: service)
        })
        XCTAssertEqual(checks, ["list-A/committed-import/true"])
        XCTAssertTrue(restored.checkedItemIDs.contains(remoteID))
        XCTAssertFalse(restored.checkedItemIDs.contains(local.id))
        XCTAssertEqual(restored.allShoppingItems.filter { $0.clientId == key }.count, 1)
        XCTAssertTrue(try XCTUnwrap(remote.shoppingList.sections[0].items.first { $0.id == remoteID }).checked)
        let relaunched = CoreLoopStore()
        relaunched.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        XCTAssertTrue(try XCTUnwrap(relaunched.allShoppingItems.first { $0.id == remoteID }).checked)
    }

    func testLostImportResponseResolvesDeletionBeforePublishingRemoteRow() async throws {
        let (core, service) = setup()
        let key = UUID().uuidString.lowercased()
        let remoteID = "committed-import"
        var remote = makePlan("A")
        service.add = { _ in
            remote.shoppingList.sections[0].items.append(self.committedImport(id: remoteID, clientID: key))
            throw ReasiServiceError.offline
        }
        try await completeWithinTimeout(Task {
            _ = await core.addImportedCandidate(candidate(), idempotencyKey: key,
                supabase: service, analytics: AnalyticsService())
        })
        core.deleteItem(try XCTUnwrap(core.allShoppingItems.first { $0.clientId == key }),
            supabase: service, analytics: AnalyticsService())
        let restored = CoreLoopStore()
        restored.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        service.fetch = { _ in remote }
        service.add = { _ in remoteID }
        let deleting = Gate<Void>()
        service.delete = { item, _ in
            await deleting.wait()
            remote.shoppingList.sections[0].items.removeAll { $0.id == item }
        }
        let restoring = Task { await restored.restoreLatestPlan(supabase: service, selectedStore: FixtureStores.store(id: .topRyde)!) }
        try await deleting.started()
        XCTAssertFalse(restored.allShoppingItems.contains { $0.id == remoteID }, "Do not expose a tombstoned row while deletion is in flight")
        deleting.resume(())
        try await completeWithinTimeout(restoring)
        try await completeWithinTimeout(Task { await restored.flushPendingShoppingChanges(supabase: service) })
        XCTAssertEqual(service.deleted, ["list-A/committed-import"])
        XCTAssertFalse(remote.shoppingList.sections[0].items.contains { $0.id == remoteID })
        XCTAssertFalse(restored.allShoppingItems.contains { $0.id == remoteID })
        let relaunched = CoreLoopStore()
        relaunched.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        XCTAssertFalse(relaunched.allShoppingItems.contains { $0.id == remoteID })
    }

    private func committedImport(id: String, clientID: String) -> ShoppingListItem {
        ShoppingListItem(id: id, name: "Rice", quantity: "1", checked: false,
            aisleLabel: nil, sectionType: .unknown, product: ProductSnapshot(candidate: candidate()),
            importedCandidate: candidate(), clientId: clientID)
    }

    func testRejectedConditionalManualSelectionDoesNotChangeLocalProduct() async throws {
        let (core, service) = setup()
        let previous = core.allShoppingItems[0]
        service.select = { false }
        var replacement = candidate()
        replacement.sku = "replacement"
        do {
            try await core.selectProduct(replacement, for: previous, actualPriceAud: nil,
                supabase: service, analytics: AnalyticsService())
            XCTFail("A rejected conditional save must be reported")
        } catch {}
        XCTAssertEqual(core.allShoppingItems[0], previous)
        XCTAssertEqual(core.checkedItemIDs, ["rice"])
    }

    func testHistoryCanOpenPreviousListsPendingImportWhileOffline() async throws {
        let (core, service) = setup()
        service.add = { _ in throw ReasiServiceError.offline }
        _ = await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService())
        try await generateB(core, service)
        service.fetch = { _ in self.makePlan("A") }
        await core.selectRecentPlan(id: "A", supabase: service)
        XCTAssertEqual(core.plan.id, "A")
        XCTAssertEqual(core.allShoppingItems.count, 2)
        XCTAssertTrue(core.allShoppingItems.contains { $0.id.hasPrefix("local-import-") })
    }

    func testAssistantQuantityEditWhileProductSaveIsSuspendedRejectsOldSnapshot() async throws {
        let core = CoreLoopStore(plan: makePlan("A"))
        core.applyAssistantMutations([mutation(quantity: "1 kg")])
        let gate = Gate<Bool>()
        var product = candidate()
        product.sku = "coles-rice"
        let matching = Task {
            await core.resolveMissingShoppingProducts(search: { _, _ in [product] }, save: { _ in await gate.wait() })
        }
        try await gate.started()
        core.applyAssistantMutations([mutation(quantity: "2 kg")])
        gate.resume(true)
        await matching.value
        XCTAssertEqual(core.allShoppingItems[0].quantity, "2 kg")
        XCTAssertNil(core.allShoppingItems[0].product, "The price calculated for 1 kg must not apply to 2 kg")
    }

    func testPendingCheckOnPreviousListSurvivesRelaunch() async throws {
        let (core, service) = setup()
        service.check = { _, _, _ in throw ReasiServiceError.offline }
        core.toggleItem(core.allShoppingItems[0], supabase: service, analytics: AnalyticsService())
        await core.flushPendingShoppingChanges(supabase: service)
        try await generateB(core, service)
        let restored = CoreLoopStore()
        restored.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        var sent: [String] = []
        service.check = { item, list, checked in sent.append("\(list)/\(item)/\(checked)") }
        await restored.flushPendingShoppingChanges(supabase: service)
        XCTAssertEqual(sent, ["list-A/rice/false"])
        XCTAssertTrue(restored.allShoppingItems[0].checked)
    }

    func testExplicitImportTombstoneSurvivesSignoutAndRelaunch() async throws {
        let (core, service) = setup()
        let userID = service.currentUserId
        service.add = { _ in throw ReasiServiceError.offline }
        _ = await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService())
        core.deleteItem(core.allShoppingItems.last!, supabase: service, analytics: AnalyticsService())
        core.activateUser(nil, selectedStore: FixtureStores.store(id: .topRyde)!)
        let restored = CoreLoopStore()
        restored.activateUser(userID, selectedStore: FixtureStores.store(id: .topRyde)!)
        service.add = { _ in "persisted-item" }
        await restored.flushPendingShoppingChanges(supabase: service)
        XCTAssertEqual(service.deleted, ["list-A/persisted-item"])
        XCTAssertEqual(restored.allShoppingItems.map(\.id), ["rice"])
    }

    func testFinishCapturesListBeforePendingFlushSuspends() async throws {
        let (core, service) = setup()
        let gate = Gate<String?>()
        service.add = { _ in throw ReasiServiceError.offline }
        _ = await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService())
        service.add = { _ in await gate.wait() }
        var finishedIDs: [String] = []
        let original = service.finish
        service.finish = { list in finishedIDs.append(list.id); return try await original(list) }
        let finishing = Task { await core.finishShopping(supabase: service, analytics: AnalyticsService()) }
        try await gate.started()
        try await generateB(core, service)
        gate.resume("persisted-item")
        _ = await finishing.value
        XCTAssertEqual(finishedIDs, ["list-A"])
        XCTAssertEqual(core.plan.shoppingList.status, .active)
    }

    func testPendingImportOnPreviousListSurvivesRelaunch() async throws {
        let (core, service) = setup()
        service.add = { _ in throw ReasiServiceError.offline }
        _ = await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService())
        try await generateB(core, service)
        let restored = CoreLoopStore()
        restored.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        service.inserted = []
        service.add = { _ in "persisted-item" }
        await restored.flushPendingShoppingChanges(supabase: service)
        XCTAssertEqual(service.inserted, ["list-A"])
        XCTAssertEqual(restored.plan.id, "B")
    }

    func testCrossRetailerSwitchInvalidatesSelectionButPreservesChecksAndIntent() async throws {
        let (core, service) = setup()
        let target = FixtureStores.store(id: .woolworthsRhodes)!
        service.regroup = { _, _ in
            let old = core.plan
            return WeekPlan(id: old.id, source: old.source, storeId: target.id, storeName: target.name,
                weekLabel: old.weekLabel, planningNotes: old.planningNotes, meals: old.meals,
                shoppingList: ShoppingList(id: old.shoppingList.id, storeId: target.id,
                    storeName: target.name, sections: old.shoppingList.sections))
        }
        core.requestStoreSwitch(to: target, appState: AppState(), supabase: service, analytics: AnalyticsService())
        try await waitUntil { core.plan.storeId == target.id && !core.isSwitchingStore }
        let item = core.allShoppingItems[0]
        XCTAssertNil(item.product)
        XCTAssertNil(item.importedCandidate)
        XCTAssertEqual(item.name, "Rice")
        XCTAssertEqual(item.quantity, "500 g")
        XCTAssertEqual(item.clientId, "stable-client")
        XCTAssertEqual(core.checkedItemIDs, ["rice"])
    }

    func testNewPlanDoesNotDeleteDelayedImport() async throws {
        let (core, service) = setup()
        let gate = Gate<String?>()
        service.add = { _ in await gate.wait() }
        let adding = Task { await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService()) }
        try await gate.started()
        try await generateB(core, service)
        gate.resume("persisted-item")
        _ = await adding.value
        await core.flushPendingShoppingChanges(supabase: service)
        XCTAssertTrue(service.deleted.isEmpty, "A queue reset is not deletion intent")
        XCTAssertEqual(core.plan.id, "B")
    }

    func testExplicitDeletionOfDelayedImportSurvivesNewPlan() async throws {
        let (core, service) = setup()
        let gate = Gate<String?>()
        service.add = { _ in await gate.wait() }
        let adding = Task { await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService()) }
        try await gate.started()
        core.deleteItem(core.allShoppingItems.last!, supabase: service, analytics: AnalyticsService())
        try await generateB(core, service)
        gate.resume("persisted-item")
        _ = await adding.value
        await core.flushPendingShoppingChanges(supabase: service)
        XCTAssertEqual(service.deleted, ["list-A/persisted-item"])
    }

    func testFinishResponseDoesNotCompleteNewPlan() async throws {
        let (core, service) = setup()
        let gate = Gate<ShoppingTripSummary>()
        let originalFinish = service.finish
        service.finish = { _ in await gate.wait() }
        let finishing = Task { await core.finishShopping(supabase: service, analytics: AnalyticsService()) }
        try await gate.started()
        let trip = try! await originalFinish(core.plan.shoppingList)
        try await generateB(core, service)
        service.check = { _, _, _ in throw ReasiServiceError.offline }
        core.toggleItem(core.allShoppingItems[0], supabase: service, analytics: AnalyticsService())
        await core.flushPendingShoppingChanges(supabase: service)
        gate.resume(trip)
        _ = await finishing.value
        XCTAssertEqual(core.plan.id, "B")
        XCTAssertEqual(core.plan.shoppingList.status, .active)
        XCTAssertNil(core.lastShoppingTrip)
        let restored = CoreLoopStore()
        restored.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        var sent: [String] = []
        service.check = { item, list, checked in sent.append("\(list)/\(item)/\(checked)") }
        await restored.flushPendingShoppingChanges(supabase: service)
        XCTAssertEqual(sent, ["list-B/rice/false"], "Finishing A must not discard B's pending check")
    }

    func testCancelWhileStartIsSuspendedSurvivesResponse() async throws {
        let (core, service) = setup()
        let gate = Gate<WeekPlanGenerationStartResult>()
        service.start = { await gate.wait() }
        core.startWeekPlanGeneration(store: FixtureStores.store(id: .topRyde)!, supabase: service,
            analytics: AnalyticsService(), appState: AppState())
        try await gate.started()
        defer { core.pauseGenerationPolling() }
        core.cancelGeneration(supabase: service, analytics: AnalyticsService(), appState: AppState())
        gate.resume(.request(request("job-A")))
        try await waitUntil { core.generationState.isCancelled }
        XCTAssertEqual(service.cancelled, ["job-A"])
        XCTAssertTrue(core.generationState.isCancelled)
        core.pauseGenerationPolling()
    }

    func testImportResponseAfterAccountSwitchDoesNotDeleteOrPopulateOtherAccount() async throws {
        let (core, service) = setup()
        let gate = Gate<String?>()
        service.add = { _ in await gate.wait() }
        let adding = Task { await core.addImportedCandidate(candidate(), idempotencyKey: UUID().uuidString,
            supabase: service, analytics: AnalyticsService()) }
        try await gate.started()
        service.currentUserId = UUID().uuidString
        core.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        gate.resume("persisted-item")
        _ = await adding.value
        await core.flushPendingShoppingChanges(supabase: service)
        XCTAssertTrue(service.deleted.isEmpty)
        XCTAssertFalse(core.hasPlan)
    }

    private func setup() -> (CoreLoopStore, SupabaseService) {
        let service = SupabaseService()
        let core = CoreLoopStore()
        core.activateUser(service.currentUserId, selectedStore: FixtureStores.store(id: .topRyde)!)
        core.plan = makePlan("A")
        core.hasPlan = true
        core.checkedItemIDs = ["rice"]
        return (core, service)
    }

    private func generateB(_ core: CoreLoopStore, _ service: SupabaseService) async throws {
        service.start = { .fixture(self.makePlan("B")) }
        core.startWeekPlanGeneration(store: FixtureStores.store(id: .topRyde)!, supabase: service,
            analytics: AnalyticsService(), appState: AppState())
        try await waitUntil { core.plan.id == "B" && !core.hasPendingGeneration }
        XCTAssertEqual(core.plan.id, "B")
    }

    #endif

    private func mutation(quantity: String?) -> AssistantListMutation {
        AssistantListMutation(operation: "update", itemId: "rice", name: "Rice", quantity: quantity,
            checked: true, sectionLabel: nil, sectionSortKey: nil, sectionType: nil, aisleLabel: nil)
    }

    private func candidate() -> ProductCandidate {
        ProductCandidate(observationId: nil, name: "Rice", brand: nil, size: "500 g", priceAud: 5,
            unitPriceAud: nil, unitQuantity: nil, unitMeasure: nil, comparablePrice: nil,
            imageUrl: URL(string: "https://example.test/rice.jpg"), productUrl: nil, sourceName: "Coles", sourceUrl: nil, capturedAt: "2026-09-30",
            freshnessLabel: "Captured", confidence: .high, confidenceReason: "fixture", uncertaintyText: "",
            retailer: "coles")
    }

    private func makePlan(_ id: String) -> WeekPlan {
        let item = ShoppingListItem(id: "rice", name: "Rice", quantity: "500 g", checked: true,
            aisleLabel: nil, sectionType: .unknown, product: ProductSnapshot(candidate: candidate()),
            importedCandidate: candidate(), clientId: "stable-client")
        return WeekPlan(id: id, source: .supabase, storeId: .topRyde, storeName: "Coles",
            weekLabel: "Week", planningNotes: "", meals: [], shoppingList: ShoppingList(id: "list-\(id)",
                storeId: .topRyde, storeName: "Coles", sections: [ShoppingListSection(label: "Pantry",
                    sortKey: 1, type: .unknown, items: [item])]))
    }
}

#if CORE_LOOP_HOST_TESTS
@MainActor private final class Gate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value { await withCheckedContinuation { continuation = $0 } }
    func started() async throws { try await waitUntil { self.continuation != nil } }
    func resume(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor private func completeWithinTimeout(_ task: Task<Void, Never>) async throws {
    var completed = false
    let observer = Task {
        await task.value
        completed = true
    }
    defer {
        observer.cancel()
        task.cancel()
    }
    try await waitUntil { completed }
}
private enum WaitError: Error { case timedOut }
#endif
