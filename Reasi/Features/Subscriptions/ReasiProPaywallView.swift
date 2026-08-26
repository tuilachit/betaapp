import SwiftUI

struct ReasiProPaywallView: View {
    let reason: String
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RevenueCatService.self) private var revenueCat
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics

    @State private var selectedPlanId: String?
    @State private var message: String?
    @State private var needsAccessRefresh = false
    @State private var didTrackView = false
    @State private var isRefreshingAccess = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                header
                benefits
                plans

                if let message {
                    Label(message, systemImage: needsAccessRefresh ? "arrow.triangle.2.circlepath" : "exclamationmark.circle")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(needsAccessRefresh ? Color.reasi.warning : Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                primaryAction
                renewalDisclosure
                purchaseLinks
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.top, ReasiSpacing.s4)
            .padding(.bottom, ReasiSpacing.s8)
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isTransactionActive)
        .task {
            if !didTrackView {
                didTrackView = true
                analytics.capture(.subscriptionPaywallViewed, properties: [
                    "trigger": .string("second_plan")
                ])
            }
            needsAccessRefresh = shouldRefreshExistingPurchase
            if needsAccessRefresh {
                await refreshServerAccess()
                return
            }
            await revenueCat.loadPaywall()
            selectDefaultPlan()
        }
        .onChange(of: revenueCat.planOptions) { _, _ in
            selectDefaultPlan()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack {
                Label("Reasi Pro", systemImage: "sparkles")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.background)
                    .padding(.horizontal, ReasiSpacing.s3)
                    .padding(.vertical, ReasiSpacing.s2)
                    .background(Color.reasi.text, in: Capsule())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: 44, height: 44)
                        .background(Color.reasi.surfaceHigh, in: Circle())
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(isTransactionActive)
                .accessibilityLabel("Close")
            }

            Text("Keep planning without starting over")
                .font(ReasiTypography.title)
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            benefit("Generate a fresh, cookable week whenever you need one", symbol: "calendar.badge.plus")
            benefit("Plan again when your budget, household, or cravings change", symbol: "arrow.triangle.2.circlepath")
            benefit("Existing plans and lists stay available without Pro", symbol: "lock.open")
        }
    }

    private func benefit(_ title: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: ReasiSpacing.s3) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 26)
            Text(title)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if needsAccessRefresh {
            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                Text("Finish updating your access")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("Your App Store purchase is safe. Reasi just needs to confirm access with your account.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        } else if revenueCat.isLoading && revenueCat.planOptions.isEmpty {
            VStack(spacing: ReasiSpacing.s3) {
                SkeletonBlock(height: 92, radius: ReasiRadius.lg)
                SkeletonBlock(height: 92, radius: ReasiRadius.lg)
            }
        } else if revenueCat.planOptions.isEmpty {
            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                Text("Plans are unavailable right now")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text(revenueCat.lastError ?? "Check your connection and try again.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                Button("Try again") {
                    Task { await revenueCat.loadPaywall() }
                }
                .buttonStyle(ReasiPressStyle())
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
                .disabled(revenueCat.isLoading)
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        } else {
            VStack(spacing: ReasiSpacing.s3) {
                ForEach(revenueCat.planOptions) { option in
                    planRow(option)
                }
            }
        }
    }

    private func planRow(_ option: ReasiProPlanOption) -> some View {
        let isSelected = selectedPlanId == option.id
        return Button {
            selectedPlanId = option.id
            message = nil
            ReasiHaptics.selection()
        } label: {
            HStack(spacing: ReasiSpacing.s4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.reasi.text : Color.reasi.dim)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: ReasiSpacing.s2) {
                        Text(option.kind.title)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                        if option.kind == .annual {
                            Text("BEST VALUE")
                                .font(ReasiTypography.navLabel)
                                .foregroundStyle(Color.reasi.background)
                                .padding(.horizontal, ReasiSpacing.s2)
                                .padding(.vertical, 4)
                                .background(Color.reasi.success, in: Capsule())
                        }
                    }
                    if let trialText = option.trialText {
                        Text(trialText)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.success)
                    }
                }

                Spacer(minLength: ReasiSpacing.s3)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(option.localizedPrice)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(option.kind.billingLabel)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
            }
            .padding(ReasiSpacing.s4)
            .frame(minHeight: 88)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.reasi.text : Color.reasi.border, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
        .accessibilityLabel("\(option.kind.title) plan")
        .accessibilityValue(planAccessibilityValue(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var primaryAction: some View {
        Button {
            Task {
                if needsAccessRefresh {
                    await refreshServerAccess()
                } else {
                    await purchaseSelectedPlan()
                }
            }
        } label: {
            HStack(spacing: ReasiSpacing.s3) {
                if revenueCat.isPurchasing || isRefreshingAccess {
                    ProgressView().tint(Color.reasi.background)
                }
                Text(primaryActionTitle)
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
        .disabled(isPrimaryActionDisabled)
        .opacity(isPrimaryActionDisabled ? 0.45 : 1)
    }

    private var primaryActionTitle: String {
        if needsAccessRefresh { return "Refresh access" }
        guard let selectedOption else { return "Choose a plan" }
        if let trialText = selectedOption.trialText {
            return "Start \(trialText.lowercased())"
        }
        return "Continue with \(selectedOption.kind.title.lowercased())"
    }

    private var isPrimaryActionDisabled: Bool {
        (!needsAccessRefresh && selectedPlanId == nil)
            || (!needsAccessRefresh && !revenueCat.isReadyForPurchases)
            || revenueCat.isPurchasing
            || revenueCat.isRestoring
            || isRefreshingAccess
    }

    private var isTransactionActive: Bool {
        revenueCat.isPurchasing || revenueCat.isRestoring || isRefreshingAccess
    }

    private var shouldRefreshExistingPurchase: Bool {
        revenueCat.isReasiProActive
            || revenueCat.accessRefreshPending
            || revenueCat.serverAccess?.isPro == true
    }

    private var renewalDisclosure: some View {
        Group {
            if let selectedOption {
                let opening = selectedOption.trialText.map {
                    "\($0), then \(selectedOption.localizedPrice) \(selectedOption.kind.billingLabel)."
                } ?? "\(selectedOption.localizedPrice) \(selectedOption.kind.billingLabel)."
                Text("\(opening) Subscription renews automatically unless cancelled at least 24 hours before the current period ends.")
            } else {
                Text("Payment is charged to your Apple ID. Subscription terms appear after plans load.")
            }
        }
        .font(ReasiTypography.caption)
        .foregroundStyle(Color.reasi.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseLinks: some View {
        VStack(spacing: ReasiSpacing.s3) {
            Button {
                Task { await restore() }
            } label: {
                if revenueCat.isRestoring {
                    ProgressView().tint(Color.reasi.text)
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(ReasiTypography.callout)
            .foregroundStyle(Color.reasi.text)
            .disabled(revenueCat.isPurchasing || revenueCat.isRestoring || isRefreshingAccess)
            .accessibilityLabel("Restore Purchases")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ReasiSpacing.s4) {
                    legalLinks
                }
                VStack(spacing: ReasiSpacing.s3) {
                    legalLinks
                }
            }
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedOption: ReasiProPlanOption? {
        revenueCat.planOptions.first { $0.id == selectedPlanId }
    }

    @ViewBuilder
    private var legalLinks: some View {
        if let url = supabase.config.privacyPolicyURL {
            Link("Privacy", destination: url)
        }
        if let url = supabase.config.termsOfServiceURL {
            Link("Terms", destination: url)
        }
        Link("Manage Subscription", destination: revenueCat.managementURLWithFallback)
    }

    private func selectDefaultPlan() {
        guard selectedPlanId == nil || !revenueCat.planOptions.contains(where: { $0.id == selectedPlanId }) else {
            return
        }
        selectedPlanId = revenueCat.planOptions.first(where: { $0.kind == .annual })?.id
            ?? revenueCat.planOptions.first?.id
    }

    private func planAccessibilityValue(_ option: ReasiProPlanOption) -> String {
        var parts = ["\(option.localizedPrice) \(option.kind.billingLabel)"]
        if let trialText = option.trialText {
            parts.append(trialText)
        }
        if option.kind == .annual {
            parts.append("Best value")
        }
        return parts.joined(separator: ", ")
    }

    private func purchaseSelectedPlan() async {
        guard let selectedOption else { return }
        message = nil
        analytics.capture(.subscriptionPurchaseStarted, properties: [
            "product_id": .string(selectedOption.id),
            "period": .string(selectedOption.kind.rawValue)
        ])

        switch await revenueCat.purchase(planId: selectedOption.id) {
        case .cancelled:
            analytics.capture(.subscriptionPurchaseCancelled, properties: [
                "product_id": .string(selectedOption.id)
            ])
            ReasiHaptics.selection()
        case .failed(let error):
            analytics.capture(.subscriptionPurchaseFailed, properties: [
                "product_id": .string(selectedOption.id),
                "reason": .string("purchase_failed")
            ])
            message = error
            ReasiHaptics.warning()
        case .purchased:
            analytics.capture(.subscriptionPurchaseCompleted, properties: [
                "product_id": .string(selectedOption.id),
                "period": .string(selectedOption.kind.rawValue)
            ])
            needsAccessRefresh = true
            await refreshServerAccess()
        }
    }

    private func restore() async {
        message = nil
        analytics.capture(.subscriptionRestoreStarted)
        switch await revenueCat.restorePurchases() {
        case .cancelled:
            break
        case .failed(let error):
            analytics.capture(.subscriptionRestoreFailed, properties: [
                "reason": .string("restore_failed")
            ])
            message = error
            ReasiHaptics.warning()
        case .purchased:
            analytics.capture(.subscriptionRestoreCompleted)
            needsAccessRefresh = true
            await refreshServerAccess()
        }
    }

    private func refreshServerAccess() async {
        guard !isRefreshingAccess else { return }
        isRefreshingAccess = true
        defer { isRefreshingAccess = false }

        do {
            let access = try await revenueCat.refreshServerAccess(using: supabase)
            analytics.capture(.reasiProEntitlementRefreshed, properties: [
                "is_pro": .bool(access.isPro),
                "can_generate": .bool(access.canGenerate),
                "success": .bool(true)
            ])
            guard access.isPro, access.canGenerate else {
                needsAccessRefresh = true
                message = "Your purchase is still syncing. Wait a moment, then refresh access."
                ReasiHaptics.warning()
                return
            }

            needsAccessRefresh = false
            ReasiHaptics.success()
            guard supabase.currentUserId == revenueCat.syncedUserId else { return }
            dismiss()
            onUnlocked()
        } catch {
            analytics.capture(.reasiProEntitlementRefreshed, properties: [
                "success": .bool(false)
            ])
            needsAccessRefresh = true
            message = "Your purchase is safe, but access could not sync yet. Check your connection and refresh."
            ReasiHaptics.warning()
        }
    }
}
