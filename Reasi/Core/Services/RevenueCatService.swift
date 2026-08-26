import Foundation
import Observation

#if canImport(RevenueCat)
import RevenueCat
#endif

enum ReasiProPlanKind: String, Hashable {
    case monthly
    case annual

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        }
    }

    var billingLabel: String {
        switch self {
        case .monthly: "per month"
        case .annual: "per year"
        }
    }
}

struct ReasiProPlanOption: Identifiable, Hashable {
    let id: String
    let kind: ReasiProPlanKind
    let localizedPrice: String
    let trialText: String?
}

enum ReasiProPurchaseOutcome: Equatable {
    case purchased
    case cancelled
    case failed(String)
}

@MainActor
@Observable
final class RevenueCatService {
    static let entitlementId = "reasi_pro"
    static let offeringId = "default"
    static let monthlyProductId = "ai.reasi.pro.monthly"
    static let annualProductId = "ai.reasi.pro.annual"

    let config: ReasiConfig
    private(set) var status: ServiceStatus
    private(set) var planOptions: [ReasiProPlanOption] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isReasiProActive = false
    private(set) var activeProductId: String?
    private(set) var managementURL: URL?
    private(set) var serverAccess: ReasiAccessSnapshot?
    private(set) var accessRefreshPending = false
    private(set) var syncedUserId: String?
    private(set) var lastError: String?

    @ObservationIgnored private var requestedUserId: String?
    @ObservationIgnored private var identityWorker: Task<Void, Never>?
    @ObservationIgnored private var identityRevision = 0
    @ObservationIgnored private var processedIdentityRevision = 0
    @ObservationIgnored private var activePaywallLoadID: UUID?
    #if canImport(RevenueCat)
    @ObservationIgnored private var packagesByProductId: [String: Package] = [:]
    #endif

    init(config: ReasiConfig = .current) {
        self.config = config
        status = ServiceStatus(
            name: "Subscriptions",
            state: config.hasRevenueCat ? .configured : .fixtureMode,
            detail: config.hasRevenueCat
                ? "Subscription access is ready to sync."
                : "Subscription setup is not available in this build."
        )
    }

    var managementURLWithFallback: URL {
        managementURL ?? URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    var isReadyForPurchases: Bool {
        guard let syncedUserId, requestedUserId == syncedUserId else { return false }
        #if canImport(RevenueCat)
        return config.hasRevenueCat && Purchases.isConfigured && Purchases.shared.appUserID == syncedUserId
        #else
        return false
        #endif
    }

    func syncUser(userId: String?) async {
        if identityWorker == nil,
           requestedUserId == userId,
           processedIdentityRevision == identityRevision,
           syncedUserId == userId {
            return
        }

        requestedUserId = userId
        identityRevision += 1

        if identityWorker == nil {
            identityWorker = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.drainIdentityChanges()
            }
        }
        await identityWorker?.value
    }

    func refreshServerAccess(using supabase: SupabaseService) async throws -> ReasiAccessSnapshot {
        guard let expectedUserId = syncedUserId,
              requestedUserId == expectedUserId,
              supabase.currentUserId == expectedUserId else {
            throw AuthFlowError.notSignedIn
        }

        do {
            let access = try await supabase.refreshReasiProAccess()
            guard requestedUserId == expectedUserId,
                  syncedUserId == expectedUserId,
                  supabase.currentUserId == expectedUserId else {
                throw CancellationError()
            }
            serverAccess = access
            accessRefreshPending = isReasiProActive && !access.isPro
            return access
        } catch {
            if requestedUserId == expectedUserId, syncedUserId == expectedUserId {
                accessRefreshPending = isReasiProActive
            }
            throw error
        }
    }

    func refreshCustomerInfo() async {
        guard isReadyForPurchases, let expectedUserId = syncedUserId else { return }
        #if canImport(RevenueCat)
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            guard isCurrentRevenueCatUser(expectedUserId) else { return }
            applyCustomerInfo(customerInfo)
        } catch {
            guard requestedUserId == expectedUserId else { return }
            lastError = "Your subscription status could not be refreshed yet."
        }
        #endif
    }

    func loadPaywall() async {
        guard config.hasRevenueCat else {
            lastError = "Subscriptions are not configured in this build."
            return
        }

        #if canImport(RevenueCat)
        guard isReadyForPurchases, let expectedUserId = syncedUserId else {
            lastError = "Your account is still getting ready. Try again in a moment."
            return
        }
        guard !isLoading else { return }

        let loadID = UUID()
        activePaywallLoadID = loadID
        isLoading = true
        lastError = nil
        defer {
            if activePaywallLoadID == loadID {
                activePaywallLoadID = nil
                isLoading = false
            }
        }

        applyCustomerInfo(Purchases.shared.cachedCustomerInfo)

        async let customerInfoRequest: CustomerInfo? = try? await Purchases.shared.customerInfo()
        async let offeringsRequest: Offerings? = try? await Purchases.shared.offerings()
        let (customerInfo, offerings) = await (customerInfoRequest, offeringsRequest)

        guard activePaywallLoadID == loadID, isCurrentRevenueCatUser(expectedUserId) else { return }
        if let customerInfo {
            applyCustomerInfo(customerInfo)
        }
        if let offerings {
            await applyOfferings(offerings, expectedUserId: expectedUserId, loadID: loadID)
        } else {
            clearOfferingState()
        }

        guard activePaywallLoadID == loadID, isCurrentRevenueCatUser(expectedUserId) else { return }
        if planOptions.isEmpty {
            lastError = "Plans could not be loaded. Check your connection and try again."
            status = ServiceStatus(
                name: "Subscriptions",
                state: .unavailable,
                detail: lastError ?? "Plans unavailable."
            )
        } else {
            status = ServiceStatus(
                name: "Subscriptions",
                state: .configured,
                detail: isReasiProActive ? "Reasi Pro is active." : "Plans loaded."
            )
        }
        #endif
    }

    func purchase(planId: String) async -> ReasiProPurchaseOutcome {
        guard !isPurchasing else { return .failed("A purchase is already in progress.") }

        #if canImport(RevenueCat)
        guard isReadyForPurchases,
              let expectedUserId = syncedUserId,
              let package = packagesByProductId[planId] else {
            return .failed("That plan is not available right now. Refresh and try again.")
        }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return .cancelled
            }
            guard isCurrentRevenueCatUser(expectedUserId) else {
                return .failed("Your account changed before the purchase finished. Refresh access before trying again.")
            }
            applyCustomerInfo(result.customerInfo)
            accessRefreshPending = true
            return .purchased
        } catch {
            return .failed("The purchase could not be completed. Please try again.")
        }
        #else
        return .failed("Subscriptions are not available in this build.")
        #endif
    }

    func restorePurchases() async -> ReasiProPurchaseOutcome {
        guard !isRestoring else { return .failed("A restore is already in progress.") }

        #if canImport(RevenueCat)
        guard isReadyForPurchases, let expectedUserId = syncedUserId else {
            return .failed("Your account is still getting ready. Try again in a moment.")
        }

        isRestoring = true
        lastError = nil
        defer { isRestoring = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            guard isCurrentRevenueCatUser(expectedUserId) else {
                return .failed("Your account changed before restore finished. Sign in again and retry.")
            }
            applyCustomerInfo(customerInfo)
            guard isReasiProActive else {
                return .failed("No active Reasi Pro purchase was found for this App Store account.")
            }
            accessRefreshPending = true
            return .purchased
        } catch {
            return .failed("Purchases could not be restored. Check your connection and try again.")
        }
        #else
        return .failed("Subscriptions are not available in this build.")
        #endif
    }

    func refreshEntitlements() async {
        await refreshCustomerInfo()
    }

    private func drainIdentityChanges() async {
        while processedIdentityRevision < identityRevision {
            let revision = identityRevision
            let targetUserId = requestedUserId
            await transitionRevenueCat(to: targetUserId)
            processedIdentityRevision = revision
        }
        identityWorker = nil
    }

    private func transitionRevenueCat(to userId: String?) async {
        if syncedUserId != userId {
            resetCustomerState(clearServerAccess: true)
            syncedUserId = nil
        }

        guard config.hasRevenueCat else {
            status = ServiceStatus(
                name: "Subscriptions",
                state: .fixtureMode,
                detail: "Subscription setup is not available in this build."
            )
            return
        }

        #if canImport(RevenueCat)
        guard let userId else {
            do {
                if Purchases.isConfigured, !Purchases.shared.isAnonymous {
                    _ = try await Purchases.shared.logOut()
                }
            } catch {
                // Local access is cleared even if RevenueCat cannot reach the network.
            }
            guard requestedUserId == nil else { return }
            resetCustomerState(clearServerAccess: true)
            syncedUserId = nil
            return
        }

        do {
            let cachedCustomerInfo: CustomerInfo?
            if !Purchases.isConfigured {
                let purchases = Purchases.configure(
                    withAPIKey: config.revenueCatPublicKey,
                    appUserID: userId
                )
                cachedCustomerInfo = purchases.cachedCustomerInfo
            } else if Purchases.shared.appUserID != userId {
                let result = try await Purchases.shared.logIn(userId)
                cachedCustomerInfo = result.customerInfo
            } else {
                cachedCustomerInfo = Purchases.shared.cachedCustomerInfo
            }

            guard requestedUserId == userId, Purchases.shared.appUserID == userId else { return }
            syncedUserId = userId
            applyCustomerInfo(cachedCustomerInfo)
            status = ServiceStatus(
                name: "Subscriptions",
                state: .configured,
                detail: "Subscription access is connected."
            )

            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                guard isCurrentRevenueCatUser(userId) else { return }
                applyCustomerInfo(customerInfo)
            } catch {
                guard requestedUserId == userId else { return }
                lastError = "Your subscription status could not be refreshed yet."
            }
        } catch {
            guard requestedUserId == userId else { return }
            resetCustomerState(clearServerAccess: true)
            syncedUserId = nil
            lastError = "Your subscription account could not be connected yet."
            status = ServiceStatus(
                name: "Subscriptions",
                state: .unavailable,
                detail: lastError ?? "Subscription status unavailable."
            )
        }
        #else
        resetCustomerState(clearServerAccess: true)
        #endif
    }

    private func resetCustomerState(clearServerAccess: Bool) {
        activePaywallLoadID = nil
        isLoading = false
        isReasiProActive = false
        activeProductId = nil
        managementURL = nil
        planOptions = []
        accessRefreshPending = false
        lastError = nil
        if clearServerAccess {
            serverAccess = nil
        }
        #if canImport(RevenueCat)
        packagesByProductId = [:]
        #endif
    }

    #if canImport(RevenueCat)
    private func isCurrentRevenueCatUser(_ userId: String) -> Bool {
        requestedUserId == userId
            && syncedUserId == userId
            && Purchases.isConfigured
            && Purchases.shared.appUserID == userId
    }

    private func applyCustomerInfo(_ customerInfo: CustomerInfo?) {
        guard let customerInfo else { return }
        let entitlement = customerInfo.entitlements.active[Self.entitlementId]
        isReasiProActive = entitlement != nil
        activeProductId = entitlement?.productIdentifier
        managementURL = customerInfo.managementURL
        if entitlement != nil, serverAccess?.isPro != true {
            accessRefreshPending = true
        }
    }

    private func clearOfferingState() {
        packagesByProductId = [:]
        planOptions = []
    }

    private func applyOfferings(_ offerings: Offerings, expectedUserId: String, loadID: UUID) async {
        clearOfferingState()
        guard let offering = offerings[Self.offeringId] ?? offerings.current else { return }

        let supportedProductIDs = Set([Self.monthlyProductId, Self.annualProductId])
        var uniquePackages: [String: Package] = [:]
        for package in offering.availablePackages {
            let productId = package.storeProduct.productIdentifier
            guard supportedProductIDs.contains(productId), uniquePackages[productId] == nil else { continue }
            uniquePackages[productId] = package
        }

        let packages = Array(uniquePackages.values)
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: packages.map(\.storeProduct.productIdentifier)
        )
        guard activePaywallLoadID == loadID, isCurrentRevenueCatUser(expectedUserId) else { return }

        packagesByProductId = uniquePackages
        planOptions = packages.compactMap { package in
            let productId = package.storeProduct.productIdentifier
            let kind: ReasiProPlanKind
            switch productId {
            case Self.monthlyProductId:
                kind = .monthly
            case Self.annualProductId:
                kind = .annual
            default:
                return nil
            }
            let isTrialEligible = eligibility[productId]?.status == .eligible
            return ReasiProPlanOption(
                id: productId,
                kind: kind,
                localizedPrice: package.localizedPriceString,
                trialText: isTrialEligible ? trialText(for: package) : nil
            )
        }
        .sorted { left, right in
            left.kind == .annual && right.kind != .annual
        }
    }

    private func trialText(for package: Package) -> String? {
        guard let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return "Free trial"
        }
        return "\(period.value) \(unit) free"
    }
    #endif
}
