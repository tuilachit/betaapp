import XCTest
@testable import Reasi

@MainActor
final class ReasiPreferenceIdentityTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "PreferenceIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func completed(_ household: HouseholdChoice, budget: Double? = 120) -> OnboardingPreferences {
        var preferences = OnboardingPreferences.empty
        preferences.household = household
        preferences.weeklyGroceryBudgetAud = budget
        preferences.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return preferences
    }

    func testActiveSessionAccountSwitchLoadsRemoteWithoutUploadingPreviousAccount() async {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles = ["A": completed(.justMe), "B": completed(.fivePlus)]
        let store = OnboardingStore(defaults: defaults())
        let app = AppState()
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        remote.currentUserId = "B"
        XCTAssertTrue(remote.isSignedIn)
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(store.preferences.household, .fivePlus)
        XCTAssertTrue(remote.writes.isEmpty)
    }

    func testRelaunchMergesPendingBudgetRemovalWithCanonicalRemoteHousehold() async {
        let local = defaults()
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: local)
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        var edit = store.preferences
        edit.weeklyGroceryBudgetAud = nil
        store.updateProfilePreferences(edit)
        remote.profiles["A"] = completed(.fivePlus)
        let relaunched = OnboardingStore(defaults: local)
        await relaunched.syncAfterAuthentication(supabase: remote, appState: AppState())
        XCTAssertNil(relaunched.preferences.weeklyGroceryBudgetAud)
        XCTAssertEqual(relaunched.preferences.household, .fivePlus)
        XCTAssertEqual(remote.writes.count, 1)
        XCTAssertNil(remote.writes.first?.1.weeklyGroceryBudgetAud)
    }

    func testDelayedAccountAFetchCannotReplaceAccountB() async {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles = ["A": completed(.justMe), "B": completed(.fivePlus)]
        let store = OnboardingStore(defaults: defaults())
        let app = AppState()
        remote.beforeFetchReturn = {
            remote.beforeFetchReturn = nil
            remote.currentUserId = "B"
            await store.syncAfterAuthentication(supabase: remote, appState: app)
        }
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(store.preferences.household, .fivePlus)
    }

    func testPendingEditsStayWithTheirAccountAcrossSignOutAndSignIn() async {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles = ["A": completed(.justMe), "B": completed(.fivePlus)]
        let store = OnboardingStore(defaults: defaults())
        let app = AppState()
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        remote.currentUserId = nil
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertFalse(store.hasCompleted)
        remote.currentUserId = "B"
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(store.preferences.weeklyGroceryBudgetAud, 120)
        remote.currentUserId = "A"
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(store.preferences.weeklyGroceryBudgetAud, 42)
        XCTAssertEqual(remote.writes.map(\.0), ["A"])
    }

    func testSaveReceiptCannotClearNewerPendingRevision() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        remote.beforeSaveReturn = {
            remote.beforeSaveReturn = nil
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
        }
        try await store.syncPendingPreferences(supabase: remote)
        try await store.syncPendingPreferences(supabase: remote)
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.writes.map { $0.1.weeklyGroceryBudgetAud }, [42, 80])
    }

    func testLateSaveReceiptCannotClearOtherAccountPendingEdits() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles = ["A": completed(.justMe), "B": completed(.fivePlus)]
        let store = OnboardingStore(defaults: defaults())
        let app = AppState()
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        remote.beforeSaveReturn = {
            remote.beforeSaveReturn = nil
            remote.currentUserId = "B"
            await store.syncAfterAuthentication(supabase: remote, appState: app)
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
        }
        do {
            try await store.syncPendingPreferences(supabase: remote)
            XCTFail("Account switch must cancel the old acknowledgment")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.writes.map(\.0), ["A", "B"])
        XCTAssertEqual(remote.writes.last?.1.weeklyGroceryBudgetAud, 80)
    }

    func testCurrentAnonymousDraftWinsOverLegacyDraft() throws {
        let local = defaults()
        var legacy = OnboardingPreferences.empty; legacy.household = .justMe
        var current = OnboardingPreferences.empty; current.household = .fivePlus
        local.set(try JSONEncoder().encode(legacy), forKey: "reasi.onboarding.preferences.v1")
        local.set(try JSONEncoder().encode(current), forKey: "reasi.preferences.v2.anonymous")
        XCTAssertEqual(OnboardingStore(defaults: local).preferences.household, .fivePlus)
    }

    func testNewAccountSignInPreservesOnboardingDraftAndPosition() async {
        let store = OnboardingStore(defaults: defaults())
        store.currentStep = .signIn
        store.preferences.household = .two
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        XCTAssertEqual(store.currentStep, .signIn)
        XCTAssertEqual(store.preferences.household, .two)
        XCTAssertFalse(store.hasCompleted)
        XCTAssertTrue(remote.writes.isEmpty)
    }

    func testNewAccountTriggerDefaultRowDoesNotOverwriteAnonymousChoices() async {
        let store = OnboardingStore(defaults: defaults())
        store.currentStep = .signIn
        store.preferences.household = .fivePlus
        store.preferences.selectedPurposes = [.reduceFoodWaste]
        store.preferences.foodStyles = [.vegetarian]
        store.preferences.selectedStoreId = .eastVillage
        store.preferences.spendingCoachTone = .direct
        let draft = store.preferences
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        var triggerRow = OnboardingPreferences.empty
        triggerRow.selectedStoreId = .topRyde
        remote.profiles["A"] = triggerRow
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        XCTAssertEqual(store.preferences, draft)
        XCTAssertEqual(store.currentStep, .signIn)
        XCTAssertFalse(store.hasCompleted)
        XCTAssertTrue(remote.writes.isEmpty)
    }

    func testDelayedHydrationCannotUndoSuccessfullySavedBudget() async {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: defaults())
        let app = AppState()
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        remote.beforeFetchReturn = {
            remote.beforeFetchReturn = nil
            var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
            store.updateProfilePreferences(edit)
            do { try await store.syncPendingPreferences(supabase: remote) }
            catch { XCTFail("Save should succeed: \(error)") }
        }
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(remote.profiles["A"]?.weeklyGroceryBudgetAud, 42)
        XCTAssertEqual(store.preferences.weeklyGroceryBudgetAud, 42)
    }

    func testBudgetOnlySaveReconcilesRemoteHouseholdBeforeSaving() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        remote.profiles["A"] = completed(.fivePlus)
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = nil
        store.updateProfilePreferences(edit)
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.profiles["A"]?.household, .fivePlus)
        XCTAssertNil(remote.profiles["A"]?.weeklyGroceryBudgetAud)
        XCTAssertEqual(store.preferences.household, .justMe)
    }

    func testBudgetOnlySaveKeepsLocalStoreConsistentUntilNormalHydration() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        var initial = completed(.justMe); initial.selectedStoreId = .topRyde
        remote.profiles["A"] = initial
        let store = OnboardingStore(defaults: defaults())
        let app = AppState(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: app)
        var changedRemote = completed(.fivePlus); changedRemote.selectedStoreId = .eastVillage
        remote.profiles["A"] = changedRemote
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = nil
        store.updateProfilePreferences(edit)

        try await store.syncPendingPreferences(supabase: remote)

        XCTAssertEqual(remote.profiles["A"]?.selectedStoreId, .eastVillage)
        XCTAssertEqual(remote.profiles["A"]?.household, .fivePlus)
        XCTAssertNil(remote.profiles["A"]?.weeklyGroceryBudgetAud)
        XCTAssertEqual(store.preferences.selectedStoreId, .topRyde)
        XCTAssertEqual(app.selectedStore.id, .topRyde)
        XCTAssertEqual(store.preferences, edit)
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.writes.count, 1, "The captured local revision must be acknowledged")

        await store.syncAfterAuthentication(supabase: remote, appState: app)
        XCTAssertEqual(store.preferences.selectedStoreId, .eastVillage)
        XCTAssertEqual(app.selectedStore.id, .eastVillage)
        XCTAssertEqual(store.preferences.household, .fivePlus)
        XCTAssertEqual(remote.writes.count, 1)
    }

    func testReconciliationReadCannotSaveIntoNewAccount() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles = ["A": completed(.justMe), "B": completed(.fivePlus)]
        let store = OnboardingStore(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        remote.beforeFetchReturn = {
            remote.beforeFetchReturn = nil
            remote.currentUserId = "B"
            store.activateUser("B")
        }
        do { try await store.syncPendingPreferences(supabase: remote); XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(remote.writes.isEmpty)
    }

    func testEditDuringReconciliationRemainsPendingForRetry() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        remote.beforeFetchReturn = {
            remote.beforeFetchReturn = nil
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
        }
        do { try await store.syncPendingPreferences(supabase: remote); XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(remote.writes.isEmpty)
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.profiles["A"]?.weeklyGroceryBudgetAud, 80)
    }

    func testOverlappingSaveIsNotIssuedAndLatestEditRemainsRetryable() async throws {
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "A"
        remote.profiles["A"] = completed(.justMe)
        let store = OnboardingStore(defaults: defaults())
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        var edit = store.preferences; edit.weeklyGroceryBudgetAud = 42
        store.updateProfilePreferences(edit)
        var wasCancelled = false
        remote.beforeSaveReturn = {
            remote.beforeSaveReturn = nil
            var newer = store.preferences; newer.weeklyGroceryBudgetAud = 80
            store.updateProfilePreferences(newer)
            do { try await store.syncPendingPreferences(supabase: remote) }
            catch is CancellationError { wasCancelled = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(remote.writes.count, 1)
        try await store.syncPendingPreferences(supabase: remote)
        XCTAssertEqual(remote.writes.map { $0.1.weeklyGroceryBudgetAud }, [42, 80])
    }

    func testUnattributedLegacyCompletedPendingProfileIsNotUploadedToNextLogin() async throws {
        let local = defaults()
        let original = try JSONEncoder().encode(completed(.justMe))
        local.set(original, forKey: "reasi.onboarding.preferences.v1")
        local.set(true, forKey: "reasi.onboarding.completed.v1")
        local.set(true, forKey: "reasi.preferences.pendingSync.v1")
        let remote = PreferenceIdentityRemote()
        remote.currentUserId = "B"
        remote.profiles["B"] = completed(.fivePlus)
        let store = OnboardingStore(defaults: local)
        await store.syncAfterAuthentication(supabase: remote, appState: AppState())
        XCTAssertEqual(store.preferences.household, .fivePlus)
        XCTAssertTrue(remote.writes.isEmpty)
        XCTAssertEqual(local.data(forKey: "reasi.onboarding.preferences.v1"), original)
        XCTAssertTrue(local.bool(forKey: "reasi.preferences.pendingSync.v1"))
    }
}

@MainActor
private final class PreferenceIdentityRemote: OnboardingPreferenceService {
    var currentUserId: String?
    var isSignedIn: Bool { currentUserId != nil }
    var profiles: [String: OnboardingPreferences] = [:]
    var writes: [(String, OnboardingPreferences)] = []
    var beforeFetchReturn: (() async -> Void)?
    var beforeSaveReturn: (() async -> Void)?

    func fetchOnboardingPreferences() async throws -> OnboardingPreferences? {
        let result = currentUserId.flatMap { profiles[$0] }
        await beforeFetchReturn?()
        return result
    }

    func saveOnboardingPreferences(_ preferences: OnboardingPreferences) async throws {
        guard let id = currentUserId else { throw CancellationError() }
        profiles[id] = preferences
        writes.append((id, preferences))
        await beforeSaveReturn?()
    }
}
