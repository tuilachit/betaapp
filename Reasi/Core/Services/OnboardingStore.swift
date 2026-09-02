import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable {
    case value
    case benefit
    case purpose
    case household
    case foodStyle
    case spendingTone
    case store
    case signIn
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

    private let draftKey = "reasi.onboarding.preferences.v1"
    private let completedKey = "reasi.onboarding.completed.v1"
    private let pendingPreferenceSyncKey = "reasi.preferences.pendingSync.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Self.loadPreferences(defaults: defaults, key: draftKey) ?? .empty
        hasCompleted = defaults.bool(forKey: completedKey)
    }

    func bootstrap(
        supabase: SupabaseService,
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

        if supabase.isSignedIn {
            do {
                if let remote = try await supabase.fetchOnboardingPreferences(), remote.completedAt != nil {
                    preferences = remote
                    markPreferencesSynced()
                    applySelectedStore(to: appState)
                    persistLocal(completed: true)
                    hasCompleted = true
                    isHydrating = false
                    return
                }

                if defaults.bool(forKey: pendingPreferenceSyncKey), preferences.completedAt != nil {
                    try await supabase.saveOnboardingPreferences(preferences)
                    markPreferencesSynced()
                    applySelectedStore(to: appState)
                    persistLocal(completed: true)
                    hasCompleted = true
                    isHydrating = false
                    return
                }
            } catch {
                errorMessage = "Your saved preferences could not be loaded. Reasi is using the choices saved on this iPhone for now."
                if hasCompleted {
                    applySelectedStore(to: appState)
                    isHydrating = false
                    return
                }
            }
        }

        if hasCompleted, !supabase.isSignedIn {
            hasCompleted = false
            currentStep = .signIn
            isHydrating = false
            captureStartedIfNeeded(analytics: analytics)
            return
        }

        if hasCompleted {
            applySelectedStore(to: appState)
            if supabase.isSignedIn {
                do {
                    try await supabase.saveOnboardingPreferences(preferences)
                    markPreferencesSynced()
                } catch {
                    defaults.set(true, forKey: pendingPreferenceSyncKey)
                }
            }
        }

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
        preferences.selectedStoreId = store.id
        ReasiHaptics.selection()
        persistDraft()
        markPreferencesPendingIfCompleted()
    }

    func applyConfirmedStore(_ store: StoreSummary) {
        guard preferences.selectedStoreId != store.id else { return }
        preferences.selectedStoreId = store.id
        persistDraft()
    }

    func updateProfilePreferences(_ updated: OnboardingPreferences) {
        preferences = updated
        persistDraft()
        markPreferencesPendingIfCompleted()
    }

    func markPreferencesSynced() {
        defaults.set(false, forKey: pendingPreferenceSyncKey)
    }

    func complete(
        supabase: SupabaseService,
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
        isSaving = true
        errorMessage = nil

        preferences.completedAt = Date()
        applySelectedStore(to: appState)

        do {
            try await supabase.saveOnboardingPreferences(preferences)
            markPreferencesSynced()
        } catch {
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

    func syncAfterAuthentication(supabase: SupabaseService, appState: AppState) async {
        guard supabase.isSignedIn else { return }

        if hasCompleted {
            do {
                try await supabase.saveOnboardingPreferences(preferences)
                markPreferencesSynced()
            } catch {
                defaults.set(true, forKey: pendingPreferenceSyncKey)
            }
            return
        }

        guard let remote = try? await supabase.fetchOnboardingPreferences(), remote.completedAt != nil else {
            return
        }

        preferences = remote
        applySelectedStore(to: appState)
        persistLocal(completed: true)
        hasCompleted = true
    }

    private func applySelectedStore(to appState: AppState) {
        appState.selectStore(preferences.resolvedStore)
    }

    private func persistDraft() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: draftKey)
    }

    private func persistLocal(completed: Bool) {
        persistDraft()
        defaults.set(completed, forKey: completedKey)
    }

    private func markPreferencesPendingIfCompleted() {
        guard hasCompleted else { return }
        defaults.set(true, forKey: pendingPreferenceSyncKey)
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
