import Foundation

@main struct PreferenceHarness {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw HarnessError.assertion(message) }
    }
    @MainActor static func fixture(_ household: HouseholdChoice, budget: Double? = 120) -> OnboardingPreferences {
        var value = OnboardingPreferences.empty
        value.household = household
        value.weeklyGroceryBudgetAud = budget
        value.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return value
    }
    @MainActor static func testAccountSwitch() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OnboardingStore(defaults: defaults)
        let service = SupabaseService()
        let app = AppState()
        service.currentUserId = "A"
        service.remote = ["A": fixture(.justMe), "B": fixture(.fivePlus)]
        await store.bootstrap(supabase: service, appState: app, analytics: AnalyticsService())
        service.currentUserId = "B" // Session stays active.
        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(store.preferences.household == .fivePlus, "B must load B, not A")
        try expect(service.saves.isEmpty, "Switch must not upload A into B")
    }
    @MainActor static func testPendingRelaunchMerge() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = SupabaseService()
        service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let first = OnboardingStore(defaults: defaults)
        await first.bootstrap(supabase: service, appState: AppState(), analytics: AnalyticsService())
        var edited = first.preferences
        edited.weeklyGroceryBudgetAud = nil
        first.updateProfilePreferences(edited)
        service.remote["A"] = fixture(.fivePlus) // An unrelated edit on another device.
        let relaunched = OnboardingStore(defaults: defaults)
        await relaunched.bootstrap(supabase: service, appState: AppState(), analytics: AnalyticsService())
        try expect(relaunched.preferences.weeklyGroceryBudgetAud == nil, "Pending budget clear lost")
        try expect(relaunched.preferences.household == .fivePlus, "Untouched remote household lost")
        try expect(service.saves.last?.1.weeklyGroceryBudgetAud == nil && service.saves.count == 1, "Merged edit must retry")
    }
    @MainActor static func testStaleFetch() async throws {
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = SupabaseService()
        let app = AppState()
        service.currentUserId = "A"
        service.remote = ["A": fixture(.justMe), "B": fixture(.fivePlus)]
        service.beforeFetchReturn = {
            service.beforeFetchReturn = nil
            service.currentUserId = "B"
            await store.syncAfterAuthentication(supabase: service, appState: app)
        }
        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(store.preferences.household == .fivePlus, "Late A response overwrote B")
    }
    @MainActor static func testPendingAccountIsolation() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = SupabaseService()
        let app = AppState()
        let store = OnboardingStore(defaults: defaults)
        service.currentUserId = "A"
        service.remote = ["A": fixture(.justMe), "B": fixture(.fivePlus)]
        await store.bootstrap(supabase: service, appState: app, analytics: AnalyticsService())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        service.currentUserId = "B"
        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(store.preferences.weeklyGroceryBudgetAud == 120, "A pending budget leaked into B")
        service.currentUserId = "A"
        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(store.preferences.weeklyGroceryBudgetAud == 42, "A pending edit did not survive switching")
    }
    @MainActor static func testAnonymousMigrationPriority() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var legacy = OnboardingPreferences.empty; legacy.household = .justMe
        var current = OnboardingPreferences.empty; current.household = .fivePlus
        defaults.set(try JSONEncoder().encode(legacy), forKey: "reasi.onboarding.preferences.v1")
        defaults.set(try JSONEncoder().encode(current), forKey: "reasi.preferences.v2.anonymous")
        try expect(OnboardingStore(defaults: defaults).preferences.household == .fivePlus, "Legacy draft overwrote v2")
    }
    @MainActor static func testNewEditDuringSave() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.bootstrap(supabase: service, appState: AppState(), analytics: AnalyticsService())
        var first = store.preferences; first.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(first)
        service.beforeSaveReturn = {
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
            service.beforeSaveReturn = nil
        }
        try await store.syncPendingPreferences(supabase: service)
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.saves.map { $0.1.weeklyGroceryBudgetAud } == [42, 80], "Old receipt cleared newer edit")
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.saves.count == 2, "Successful receipt did not clear pending")
    }
    @MainActor static func testNewUserKeepsOnboardingPosition() async throws {
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.currentStep = .signIn
        store.preferences.household = .two
        let service = SupabaseService(); service.currentUserId = "A"
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        try expect(store.currentStep == .signIn, "New-user sign-in restarted onboarding")
        try expect(store.preferences.household == .two, "Anonymous onboarding draft lost")
    }
    @MainActor static func testTriggerDefaultRowKeepsDraft() async throws {
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.currentStep = .signIn
        store.preferences.household = .fivePlus
        store.preferences.selectedPurposes = [.reduceFoodWaste]
        store.preferences.foodStyles = [.vegetarian]
        store.preferences.selectedStoreId = .eastVillage
        store.preferences.spendingCoachTone = .direct
        let draft = store.preferences
        let service = SupabaseService(); service.currentUserId = "A"
        // handle_new_user creates a real incomplete preferences row, while the
        // default profiles.selected_store_id resolves to top_ryde on fetch.
        var triggerRow = OnboardingPreferences.empty
        triggerRow.selectedStoreId = .topRyde
        service.remote["A"] = triggerRow
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        try expect(store.preferences == draft, "Trigger default row overwrote anonymous survey choices")
        try expect(service.saves.isEmpty && !store.hasCompleted, "Draft must remain incomplete until confirmation")
    }
    @MainActor static func testHydrationCannotUndoAcknowledgedSave() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let app = AppState()
        await store.syncAfterAuthentication(supabase: service, appState: app)
        service.beforeFetchReturn = {
            service.beforeFetchReturn = nil
            var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
            store.updateProfilePreferences(edit)
            try! await store.syncPendingPreferences(supabase: service)
        }
        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(service.remote["A"]?.weeklyGroceryBudgetAud == 42, "Save did not reach remote fixture")
        try expect(store.preferences.weeklyGroceryBudgetAud == 42, "Delayed hydration replaced acknowledged 42 with 120")
    }
    @MainActor static func testBudgetOnlySavePreservesRemoteHousehold() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        service.remote["A"] = fixture(.fivePlus)
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = nil
        store.updateProfilePreferences(edit)
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.remote["A"]?.household == .fivePlus, "Budget-only save clobbered remote household")
        try expect(service.remote["A"]?.weeklyGroceryBudgetAud == nil, "Budget clear not saved")
        try expect(store.preferences.household == .justMe, "Budget-only save published unrelated remote household")
    }
    @MainActor static func testBudgetOnlySaveKeepsLocalStoreUntilHydration() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        var initial = fixture(.justMe); initial.selectedStoreId = .topRyde
        service.remote["A"] = initial
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let app = AppState()
        await store.syncAfterAuthentication(supabase: service, appState: app)
        var changedRemote = fixture(.fivePlus); changedRemote.selectedStoreId = .eastVillage
        service.remote["A"] = changedRemote
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = nil
        store.updateProfilePreferences(edit)

        try await store.syncPendingPreferences(supabase: service)

        try expect(service.remote["A"]?.selectedStoreId == .eastVillage, "Budget-only save clobbered remote store")
        try expect(service.remote["A"]?.household == .fivePlus, "Budget-only save clobbered remote household")
        try expect(service.remote["A"]?.weeklyGroceryBudgetAud == nil, "Budget clear not saved")
        try expect(store.preferences.selectedStoreId == .topRyde, "Budget-only save changed local store without AppState")
        try expect(app.selectedStore.id == .topRyde, "Budget-only save implicitly switched AppState")
        try expect(store.preferences == edit, "Budget-only save changed unrelated local preferences")
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.saves.count == 1, "Reconciled payload prevented acknowledgment of local edit")

        await store.syncAfterAuthentication(supabase: service, appState: app)
        try expect(store.preferences.selectedStoreId == .eastVillage && app.selectedStore.id == .eastVillage,
                   "Normal hydration must update preferences and AppState together")
        try expect(store.preferences.household == .fivePlus, "Normal hydration did not adopt remote household")
        try expect(service.saves.count == 1, "Acknowledged budget unexpectedly saved again during hydration")
    }
    @MainActor static func testSaveReconciliationRejectsAccountSwitch() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote = ["A": fixture(.justMe), "B": fixture(.fivePlus)]
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        service.beforeFetchReturn = {
            service.beforeFetchReturn = nil
            service.currentUserId = "B"
            store.activateUser("B")
        }
        do { try await store.syncPendingPreferences(supabase: service); throw HarnessError.assertion("Expected cancelled reconciliation") }
        catch is CancellationError {}
        try expect(service.saves.isEmpty, "A snapshot saved after B sign-in")
    }
    @MainActor static func testSaveReconciliationPreservesNewerEdit() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        service.beforeFetchReturn = {
            service.beforeFetchReturn = nil
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
        }
        do { try await store.syncPendingPreferences(supabase: service); throw HarnessError.assertion("Expected cancelled old edit") }
        catch is CancellationError {}
        try expect(service.saves.isEmpty, "Old edit sent after newer edit during fetch")
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.remote["A"]?.weeklyGroceryBudgetAud == 80, "Newer edit was not retryable")
    }
    @MainActor static func testOverlappingSaveKeepsLatestPending() async throws {
        let service = SupabaseService(); service.currentUserId = "A"
        service.remote["A"] = fixture(.justMe)
        let store = OnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.syncAfterAuthentication(supabase: service, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        var cancelled = false
        service.beforeSaveReturn = {
            service.beforeSaveReturn = nil
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
            do { try await store.syncPendingPreferences(supabase: service) }
            catch is CancellationError { cancelled = true }
            catch {}
        }
        try await store.syncPendingPreferences(supabase: service)
        try expect(cancelled && service.saves.count == 1, "Overlapping write was issued")
        try await store.syncPendingPreferences(supabase: service)
        try expect(service.saves.map { $0.1.weeklyGroceryBudgetAud } == [42, 80], "Latest pending edit was cleared by older save")
    }
    @MainActor static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("account switch", testAccountSwitch),
            ("pending relaunch merge", testPendingRelaunchMerge),
            ("stale fetch", testStaleFetch),
            ("pending account isolation", testPendingAccountIsolation),
            ("anonymous migration priority", testAnonymousMigrationPriority),
            ("new edit during save", testNewEditDuringSave),
            ("new-user onboarding position", testNewUserKeepsOnboardingPosition),
            ("trigger default row preserves draft", testTriggerDefaultRowKeepsDraft),
            ("late hydration after successful save", testHydrationCannotUndoAcknowledgedSave),
            ("budget-only save preserves remote fields", testBudgetOnlySavePreservesRemoteHousehold),
            ("budget-only save keeps local store until hydration", testBudgetOnlySaveKeepsLocalStoreUntilHydration),
            ("reconciliation account switch", testSaveReconciliationRejectsAccountSwitch),
            ("reconciliation newer edit", testSaveReconciliationPreservesNewerEdit),
            ("overlapping saves retain latest edit", testOverlappingSaveKeepsLatestPending),
        ]
        var failures = 0
        for (name, test) in tests {
            do { try await test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(tests.count - failures)/\(tests.count) preference regressions passed")
        if failures > 0 { exit(1) }
    }
}
