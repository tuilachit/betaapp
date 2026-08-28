import Foundation
import Observation

#if canImport(PostHog)
import PostHog
#endif

@MainActor
@Observable
final class AnalyticsService {
    let config: ReasiConfig
    private(set) var status: ServiceStatus
    private(set) var recentEvents: [String] = []

    @ObservationIgnored private var didSetupPostHog = false

    init(config: ReasiConfig = .current) {
        self.config = config

        status = ServiceStatus(
            name: "PostHog",
            state: config.hasPostHog ? .configured : .fixtureMode,
            detail: config.hasPostHog ? "Public project key is present." : "No key present; events are no-ops."
        )

        setupPostHogIfNeeded()
    }

    func capture(_ event: AnalyticsEvent, properties: [String: AnalyticsProperty] = [:]) {
        recentEvents.insert(event.rawValue, at: 0)
        recentEvents = Array(recentEvents.prefix(24))

        #if DEBUG
        print("[Reasi Analytics] \(event.rawValue) \(properties.debugDescription)")
        #endif

        guard config.hasPostHog else { return }

        #if canImport(PostHog)
        setupPostHogIfNeeded()
        PostHogSDK.shared.capture(event.rawValue, properties: properties.mapValues(\.anyValue))
        #endif
    }

    func identify(userId: String, properties: [String: AnalyticsProperty] = [:]) {
        #if DEBUG
        print("[Reasi Analytics] identify \(userId) \(properties.debugDescription)")
        #endif

        guard config.hasPostHog else { return }

        #if canImport(PostHog)
        setupPostHogIfNeeded()
        PostHogSDK.shared.identify(userId, userProperties: properties.mapValues(\.anyValue))
        #endif
    }

    func resetIdentity() {
        #if DEBUG
        print("[Reasi Analytics] reset identity")
        #endif

        guard config.hasPostHog else { return }

        #if canImport(PostHog)
        setupPostHogIfNeeded()
        PostHogSDK.shared.reset()
        #endif
    }

    func flush() {
        guard config.hasPostHog else { return }

        #if canImport(PostHog)
        setupPostHogIfNeeded()
        PostHogSDK.shared.flush()
        #endif
    }

    private func setupPostHogIfNeeded() {
        guard config.hasPostHog, !didSetupPostHog else { return }

        #if canImport(PostHog)
        let postHogConfig = PostHogConfig(
            projectToken: config.postHogKey,
            host: config.postHogHost.absoluteString
        )
        postHogConfig.flushAt = 5
        postHogConfig.flushIntervalSeconds = 5
        #if DEBUG
        postHogConfig.debug = true
        #endif
        PostHogSDK.shared.setup(postHogConfig)
        didSetupPostHog = true
        #endif
    }
}

enum AnalyticsEvent: String, CaseIterable {
    case appOpened = "app_opened"
    case coreHomeViewed = "core_home_viewed"
    case planGenerationStarted = "plan_generation_started"
    case planGenerationSucceeded = "plan_generation_succeeded"
    case planGenerationFailed = "plan_generation_failed"
    case planBuilderOpened = "plan_builder_opened"
    case planIdeaAdded = "plan_idea_added"
    case planProductRoleSelected = "plan_product_role_selected"
    case planBriefInterpreted = "plan_brief_interpreted"
    case planGapRecommendationViewed = "plan_gap_recommendation_viewed"
    case planGapRecommendationSelected = "plan_gap_recommendation_selected"
    case planConfirmed = "plan_confirmed"
    case budgetWarningViewed = "budget_warning_viewed"
    case budgetRevisionRequested = "budget_revision_requested"
    case weekPlanViewed = "week_plan_viewed"
    case shoppingListCreated = "shopping_list_created"
    case shoppingListViewed = "shopping_list_viewed"
    case shoppingItemChecked = "shopping_item_checked"
    case shoppingItemDeleted = "shopping_item_deleted"
    case shoppingAssistantListChanged = "shopping_assistant_list_changed"
    case shoppingListProgress = "shopping_list_progress_25_50_75_100"
    case weeklyReturnDetected = "weekly_return_detected"
    case storeSelected = "store_selected"
    case onboardingStarted = "onboarding_started"
    case onboardingPurposeSubmitted = "onboarding_purpose_submitted"
    case onboardingCompleted = "onboarding_completed"
    case authSignInStarted = "auth_sign_in_started"
    case authSignInCompleted = "auth_sign_in_completed"
    case signUp = "sign_up"
    case signIn = "sign_in"
    case authPasswordResetRequested = "auth_password_reset_requested"
    case accountDeletionStarted = "account_deletion_started"
    case accountDeletionCompleted = "account_deletion_completed"
    case accountDeletionFailed = "account_deletion_failed"
    case productInputStarted = "product_input_started"
    case productInputSucceeded = "product_input_succeeded"
    case productInputFailed = "product_input_failed"
    case productCandidateReviewed = "product_candidate_reviewed"
    case productCandidateAdded = "product_candidate_added"
    case productCandidateDiscarded = "product_candidate_discarded"
    case shoppingListPhotoExtracted = "shopping_list_photo_extracted"
    case productComparisonStarted = "product_comparison_started"
    case productComparisonViewed = "product_comparison_viewed"
    case shoppingAssistantOpened = "shopping_assistant_opened"
    case shoppingAssistantMessageSent = "shopping_assistant_message_sent"
    case shoppingAssistantResponseReceived = "shopping_assistant_response_received"
    case shoppingAssistantFailed = "shopping_assistant_failed"
    case subscriptionPaywallViewed = "subscription_paywall_viewed"
    case subscriptionPurchaseStarted = "subscription_purchase_started"
    case subscriptionPurchaseCompleted = "subscription_purchase_completed"
    case subscriptionPurchaseCancelled = "subscription_purchase_cancelled"
    case subscriptionPurchaseFailed = "subscription_purchase_failed"
    case subscriptionRestoreStarted = "subscription_restore_started"
    case subscriptionRestoreCompleted = "subscription_restore_completed"
    case subscriptionRestoreFailed = "subscription_restore_failed"
    case reasiProEntitlementRefreshed = "reasi_pro_entitlement_refreshed"
    case settingsUpdated = "settings_updated"
}

enum AnalyticsProperty: Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])

    var anyValue: Any {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .bool(let value):
            value
        case .stringArray(let value):
            value
        }
    }
}
