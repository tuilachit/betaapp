import Foundation
import Observation

@MainActor
protocol OnboardingPreferenceService: AnyObject, Sendable {
    var currentUserId: String? { get }
    var isSignedIn: Bool { get }
    func fetchOnboardingPreferences() async throws -> OnboardingPreferences?
    func saveOnboardingPreferences(_ preferences: OnboardingPreferences) async throws
}

extension SupabaseService: OnboardingPreferenceService {}

struct PreferenceSyncToken: Equatable {
    let userId: String
    let identityRevision: Int
    let editRevision: Int
    let preferences: OnboardingPreferences
}

private enum PreferenceField: String, CaseIterable {
    case purposes, household, foodStyles, store, budget, tone, completion

    static func changed(from old: OnboardingPreferences, to new: OnboardingPreferences) -> Set<Self> {
        var fields: Set<Self> = []
        if old.selectedPurposes != new.selectedPurposes { fields.insert(.purposes) }
        if old.household != new.household { fields.insert(.household) }
        if old.foodStyles != new.foodStyles { fields.insert(.foodStyles) }
        if old.selectedStoreId != new.selectedStoreId { fields.insert(.store) }
        if old.weeklyGroceryBudgetAud != new.weeklyGroceryBudgetAud { fields.insert(.budget) }
        if old.spendingCoachTone != new.spendingCoachTone { fields.insert(.tone) }
        if old.completedAt != new.completedAt { fields.insert(.completion) }
        return fields
    }
}

enum OnboardingStep: Int, CaseIterable {
    case value
    case benefit
    case purpose
    case household
    case foodStyle
    case spendingTone
    case store
    case signIn
    case storeGuide
    case ready

    var isSurvey: Bool {
        switch self {
        case .purpose, .household, .foodStyle, .spendingTone, .store: true
        default: false
        }
    }

    var progressIndex: Int {
        max(0, rawValue - OnboardingStep.purpose.rawValue)
    }
}

@MainActor
@Observable
final class OnboardingStore {
    private static let purposeSurveyVersion = "pain_priorities_v2"

    var currentStep: OnboardingStep = .value
    var preferences: OnboardingPreferences
    private(set) var isHydrating = true
    private(set) var hasCompleted = false
    private(set) var isSaving = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var didCaptureStarted = false
    @ObservationIgnored private var didCapturePurpose = false
    @ObservationIgnored private var activeUserId: String?
    @ObservationIgnored private var identityRevision = 0
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var hydrationRevision = 0
    @ObservationIgnored private var preferenceSaveID: UUID?
    @ObservationIgnored private var pendingFields: Set<PreferenceField> = []

    private var scope: String { activeUserId ?? "anonymous" }
    private var draftKey: String { "reasi.preferences.v2.\(scope)" }
    private var completedKey: String { "reasi.preferences.completed.v2.\(scope)" }
    private var pendingPreferenceSyncKey: String { "reasi.preferences.pendingFields.v2.\(scope)" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Self.loadPreferences(defaults: defaults, key: "reasi.preferences.v2.anonymous") ?? .empty
        // Legacy completed profiles have no owner. Never assign one to whichever
        // account signs in next; retain the old keys untouched for recovery.
        if defaults.data(forKey: "reasi.preferences.v2.anonymous") == nil,
           let legacy = Self.loadPreferences(defaults: defaults, key: "reasi.onboarding.preferences.v1"),
           legacy.completedAt == nil, !defaults.bool(forKey: "reasi.onboarding.completed.v1") {
            preferences = legacy
        }
    }

    func activateUser(_ userId: String?) {
        guard activeUserId != userId else { return }
        let continuingOnboarding = activeUserId == nil && !hasCompleted && userId != nil
        let anonymousDraft = continuingOnboarding ? preferences : .empty
        activeUserId = userId
        identityRevision += 1
        editRevision = 0
        hydrationRevision += 1
        preferenceSaveID = nil
        preferences = Self.loadPreferences(defaults: defaults, key: draftKey)
            ?? (userId == nil ? .empty : anonymousDraft)
        hasCompleted = userId != nil && defaults.bool(forKey: completedKey)
        pendingFields = Set((defaults.stringArray(forKey: pendingPreferenceSyncKey) ?? []).compactMap(PreferenceField.init(rawValue:)))
        errorMessage = nil
        isSaving = false
        if !continuingOnboarding { currentStep = .value }
    }

    func bootstrap(
        supabase: any OnboardingPreferenceService,
        appState: AppState,
        analytics: AnalyticsService
    ) async {
        guard !didBootstrap else { return }
        didBootstrap = true
        isHydrating = true

        let forceOnboarding = ProcessInfo.processInfo.arguments.contains("-ReasiForceOnboarding")
        if forceOnboarding {
            hasCompleted = false
            preferences.completedAt = nil
            currentStep = .value
            isHydrating = false
            captureStartedIfNeeded(analytics: analytics)
            return
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture")
            || ProcessInfo.processInfo.arguments.contains("-ReasiShowShoppingFixture") {
            hasCompleted = true
            isHydrating = false
            return
        }
        #endif

        await syncAfterAuthentication(supabase: supabase, appState: appState)

        isHydrating = false
        if !hasCompleted {
            captureStartedIfNeeded(analytics: analytics)
        }
    }

    func captureStartedIfNeeded(analytics: AnalyticsService) {
        guard !didCaptureStarted else { return }
        didCaptureStarted = true
        analytics.capture(.onboardingStarted, properties: [
            "survey_version": .string(Self.purposeSurveyVersion)
        ])
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        ReasiHaptics.light()
        currentStep = next
        persistDraft()
    }

    func submitPurpose(analytics: AnalyticsService, skipped: Bool = false) {
        if !didCapturePurpose {
            didCapturePurpose = true
            var properties = purposeAnalyticsProperties()
            properties["skipped"] = .bool(skipped)
            analytics.capture(.onboardingPurposeSubmitted, properties: properties)
        }
        advance()
    }

    func skipCurrentSurvey(analytics: AnalyticsService) {
        switch currentStep {
        case .purpose:
            preferences.selectedPurposes = []
            submitPurpose(analytics: analytics, skipped: true)
        case .household:
            preferences.household = nil
            advance()
        case .foodStyle:
            preferences.foodStyles = []
            advance()
        case .spendingTone:
            preferences.spendingCoachTone = .supportive
            advance()
        case .store:
            preferences.selectedStoreId = nil
            advance()
        default:
            break
        }
    }

    func toggleFoodStyle(_ style: FoodStyle) {
        if preferences.foodStyles.contains(style) {
            preferences.foodStyles.remove(style)
        } else {
            preferences.foodStyles.insert(style)
        }
        ReasiHaptics.selection()
        persistDraft()
    }

    func togglePurpose(_ purpose: OnboardingPurpose) {
        let wasSelected = preferences.selectedPurposes.contains(purpose)
        preferences.togglePurpose(purpose)
        if wasSelected || preferences.selectedPurposes.contains(purpose) {
            ReasiHaptics.selection()
            persistDraft()
        } else {
            ReasiHaptics.warning()
        }
    }

    func selectStore(_ store: StoreSummary) {
        if hasCompleted, preferences.selectedStoreId != store.id { pendingFields.insert(.store) }
        preferences.selectedStoreId = store.id
        ReasiHaptics.selection()
        persistDraft()
    }

    func applyConfirmedStore(_ store: StoreSummary) {
        guard preferences.selectedStoreId != store.id else { return }
        preferences.selectedStoreId = store.id
        persistDraft()
    }

    func updateProfilePreferences(_ updated: OnboardingPreferences) {
        if hasCompleted { pendingFields.formUnion(PreferenceField.changed(from: preferences, to: updated)) }
        preferences = updated
        persistDraft()
    }

    var pendingSyncToken: PreferenceSyncToken? {
        guard let activeUserId else { return nil }
        return PreferenceSyncToken(userId: activeUserId, identityRevision: identityRevision,
                                   editRevision: editRevision, preferences: preferences)
    }

    func markPreferencesSynced(_ token: PreferenceSyncToken?) {
        // A caller without an account/revision receipt cannot acknowledge edits.
        guard let token, token == pendingSyncToken else { return }
        hydrationRevision += 1
        pendingFields = []
        defaults.set([], forKey: pendingPreferenceSyncKey)
    }

    func syncPendingPreferences(supabase: any OnboardingPreferenceService) async throws {
        guard let token = pendingSyncToken, supabase.isSignedIn,
              supabase.currentUserId == token.userId else { throw CancellationError() }
        guard !pendingFields.isEmpty else { return }
        // One full-snapshot write per account at a time. A concurrent edit stays
        // pending instead of letting an older network write finish after it.
        guard preferenceSaveID == nil else { throw CancellationError() }
        let saveID = UUID()
        preferenceSaveID = saveID
        defer { if preferenceSaveID == saveID { preferenceSaveID = nil } }
        hydrationRevision += 1
        let hydration = hydrationRevision
        let remote = try await supabase.fetchOnboardingPreferences()
        guard !Task.isCancelled, supabase.isSignedIn,
              supabase.currentUserId == token.userId, pendingSyncToken == token,
              preferenceSaveID == saveID, hydrationRevision == hydration else { throw CancellationError() }
        // Reconcile the write only; hydration owns publishing remote fields
        // and applying the selected store to AppState together.
        let payload = remote.map { mergingPendingFields(into: $0) } ?? token.preferences
        try await supabase.saveOnboardingPreferences(payload)
        guard !Task.isCancelled, supabase.isSignedIn,
              supabase.currentUserId == token.userId, activeUserId == token.userId,
              identityRevision == token.identityRevision else { throw CancellationError() }
        markPreferencesSynced(token)
    }

    func complete(
        supabase: any OnboardingPreferenceService,
        appState: AppState,
        analytics: AnalyticsService
    ) async -> Bool {
        guard !isSaving else { return false }
        guard supabase.isSignedIn else {
            currentStep = .signIn
            errorMessage = "Sign in to save your first plan."
            ReasiHaptics.warning()
            return false
        }
        activateUser(supabase.currentUserId)
        let expectedIdentity = identityRevision
        isSaving = true
        errorMessage = nil

        preferences.completedAt = Date()
        pendingFields = Set(PreferenceField.allCases)
        persistDraft()
        let token = pendingSyncToken
        applySelectedStore(to: appState)

        do {
            try await supabase.saveOnboardingPreferences(preferences)
            guard !Task.isCancelled, identityRevision == expectedIdentity,
                  supabase.currentUserId == activeUserId else { return false }
            markPreferencesSynced(token)
        } catch {
            guard identityRevision == expectedIdentity, supabase.currentUserId == activeUserId else { return false }
            preferences.completedAt = nil
            isSaving = false
            errorMessage = "We couldn't save your choices. Check your connection and try again."
            ReasiHaptics.warning()
            return false
        }

        persistLocal(completed: true)
        hasCompleted = true
        isSaving = false

        var completionProperties = purposeAnalyticsProperties()
        completionProperties.merge([
            "household": .string(preferences.household?.rawValue ?? "skipped"),
            "household_size": .int(preferences.householdSize),
            "food_styles": .stringArray(preferences.sortedFoodStyleValues),
            "store_id": .string(preferences.resolvedStore.id.rawValue),
            "store_defaulted": .bool(preferences.selectedStoreId == nil),
            "spending_coach_tone": .string(preferences.spendingCoachTone.rawValue),
            "signed_in": .bool(supabase.isSignedIn)
        ]) { _, latest in latest }
        analytics.capture(.onboardingCompleted, properties: completionProperties)
        ReasiHaptics.success()
        return true
    }

    func syncAfterAuthentication(supabase: any OnboardingPreferenceService, appState: AppState) async {
        activateUser(supabase.isSignedIn ? supabase.currentUserId : nil)
        guard let userId = activeUserId else { return }
        let identity = identityRevision
        hydrationRevision += 1
        let hydration = hydrationRevision
        func isCurrent() -> Bool {
            !Task.isCancelled && identityRevision == identity && hydrationRevision == hydration
                && supabase.isSignedIn && supabase.currentUserId == userId
        }
        do {
            let remote = try await supabase.fetchOnboardingPreferences()
            guard isCurrent() else { return }
            let hasLocalDraft = !hasCompleted && preferences.completedAt == nil
                && (preferences != .empty || currentStep != .value)
            // The signup trigger creates an incomplete default row. It is not
            // an authoritative completed profile that can replace the survey.
            if let remote, remote.completedAt != nil || !hasLocalDraft {
                let merged = mergingPendingFields(into: remote)
                preferences = merged
                hasCompleted = merged.completedAt != nil
                persistLocal(completed: hasCompleted)
            }
            applySelectedStore(to: appState)
        } catch {
            guard isCurrent() else { return }
            errorMessage = "Your saved preferences could not be loaded. Reasi is using the choices saved on this iPhone for now."
            if hasCompleted { applySelectedStore(to: appState) }
            return
        }
        do {
            try await syncPendingPreferences(supabase: supabase)
        } catch {
            guard !Task.isCancelled, identityRevision == identity, supabase.isSignedIn,
                  supabase.currentUserId == userId else { return }
            errorMessage = "Your preference changes are saved on this iPhone and will sync when you reconnect."
        }
    }

    private func mergingPendingFields(into remote: OnboardingPreferences) -> OnboardingPreferences {
        var merged = remote
        for field in pendingFields {
            switch field {
            case .purposes: merged.selectedPurposes = preferences.selectedPurposes
            case .household: merged.household = preferences.household
            case .foodStyles: merged.foodStyles = preferences.foodStyles
            case .store: merged.selectedStoreId = preferences.selectedStoreId
            case .budget: merged.weeklyGroceryBudgetAud = preferences.weeklyGroceryBudgetAud
            case .tone: merged.spendingCoachTone = preferences.spendingCoachTone
            case .completion: merged.completedAt = preferences.completedAt
            }
        }
        return merged
    }

    private func applySelectedStore(to appState: AppState) {
        appState.selectStore(preferences.resolvedStore)
    }

    private func persistDraft() {
        editRevision += 1
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: draftKey)
        defaults.set(pendingFields.map(\.rawValue).sorted(), forKey: pendingPreferenceSyncKey)
    }

    private func persistLocal(completed: Bool) {
        persistDraft()
        defaults.set(completed, forKey: completedKey)
    }

    private func purposeAnalyticsProperties() -> [String: AnalyticsProperty] {
        let purposes = preferences.selectedPurposes
        return [
            "survey_version": .string(Self.purposeSurveyVersion),
            "purpose": .string(preferences.primaryPurpose?.rawValue ?? "skipped"),
            "primary_purpose": .string(preferences.primaryPurpose?.rawValue ?? "skipped"),
            "secondary_purpose": .string(purposes.dropFirst().first?.rawValue ?? "not_selected"),
            "tertiary_purpose": .string(purposes.dropFirst(2).first?.rawValue ?? "not_selected"),
            "purpose_tags": .stringArray(purposes.map(\.rawValue)),
            "selection_count": .int(purposes.count)
        ]
    }

    private static func loadPreferences(defaults: UserDefaults, key: String) -> OnboardingPreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnboardingPreferences.self, from: data)
    }
}
