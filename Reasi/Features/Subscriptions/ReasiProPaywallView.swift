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
    @State private var showingExitView = false
    @State private var showingDetailsSheet = false

    var body: some View {
        Group {
            if showingExitView {
                exitView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                        header
                        plans

                        if let message {
                            Label(message, systemImage: needsAccessRefresh ? "arrow.triangle.2.circlepath" : "exclamationmark.circle")
                                .font(ReasiTypography.callout)
                                .foregroundStyle(needsAccessRefresh ? Color.reasi.warning : Color.reasi.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        primaryAction
                        purchaseLinks
                    }
                    .padding(.horizontal, ReasiSpacing.s5)
                    .padding(.top, ReasiSpacing.s4)
                    .padding(.bottom, ReasiSpacing.s8)
                }
            }
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isTransactionActive)
        .sheet(isPresented: $showingDetailsSheet) {
            detailsSheet
        }
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-reasi-show-paywall-fixture") {
                revenueCat.loadDebugPaywallFixture()
            } else {
                await revenueCat.loadPaywall()
            }
            #else
            await revenueCat.loadPaywall()
            #endif
            selectDefaultPlan()
        }
        .onChange(of: revenueCat.planOptions) { _, _ in
            selectDefaultPlan()
        }
    }

    private var header: some View {
        VStack(spacing: ReasiSpacing.s4) {
            HStack {
                Spacer()
                Button {
                    showingExitView = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: 42, height: 42)
                        .background(Color.reasi.surfaceHigh, in: Circle())
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(isTransactionActive)
                .accessibilityLabel("Close paywall")
            }
            .frame(maxWidth: .infinity)

            Image("ReasiWordmark")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 108, height: 29)
                .clipped()
                .foregroundStyle(Color.reasi.text)

            Text("Reasi Pro")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)

            Text("More weeks. Less work.")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Plan, shop, and track with less effort.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var exitView: some View {
        VStack(spacing: ReasiSpacing.s6) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: 42, height: 42)
                        .background(Color.reasi.surfaceHigh, in: Circle())
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(isTransactionActive)
                .accessibilityLabel("Dismiss")
            }

            Spacer(minLength: ReasiSpacing.s8)

            Image("ReasiWordmark")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 92, height: 25)
                .clipped()
                .foregroundStyle(Color.reasi.text)

            VStack(spacing: ReasiSpacing.s3) {
                Text("Not ready yet?")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                    .multilineTextAlignment(.center)

                Text("Your current plan stays yours. Come back when you need another week.")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 300)

            VStack(spacing: ReasiSpacing.s3) {
                Button("Keep my plan") {
                    dismiss()
                }
                .buttonStyle(ReasiPrimaryButtonStyle())

                Button("View plans") {
                    showingExitView = false
                }
                .buttonStyle(ReasiPressStyle())
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.top, ReasiSpacing.s4)
        .padding(.bottom, ReasiSpacing.s8)
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
        return VStack(spacing: 0) {
            if option.kind == .annual {
                Text("BEST VALUE")
                    .font(ReasiTypography.navLabel)
                    .foregroundStyle(Color.reasi.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ReasiSpacing.s1)
                    .background(Color.reasi.success)
            }

            Button {
                selectedPlanId = option.id
                message = nil
                ReasiHaptics.selection()
            } label: {
                HStack(spacing: ReasiSpacing.s3) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.reasi.text : Color.reasi.dim)

                    VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
                        Text(option.kind.title)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                        if let trialText = option.trialText {
                            Text(trialText)
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.success)
                        }
                    }

                    Spacer(minLength: ReasiSpacing.s3)

                    VStack(alignment: .trailing, spacing: ReasiSpacing.s1) {
                        Text(option.localizedPrice)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                        Text(option.kind.billingLabel)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.muted)
                    }
                }
                .padding(.horizontal, ReasiSpacing.s4)
                .padding(.vertical, ReasiSpacing.s3)
                .frame(minHeight: 72)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReasiPressStyle())
        }
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                .stroke(
                    isSelected
                        ? (option.kind == .annual ? Color.reasi.success : Color.reasi.text)
                        : Color.reasi.border,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
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

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
                    if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            Text("Why you're seeing this")
                                .font(ReasiTypography.headline)
                                .foregroundStyle(Color.reasi.text)
                            Text(reason)
                                .font(ReasiTypography.body)
                                .foregroundStyle(Color.reasi.textMuted)
                        }
                    }
                    renewalDisclosure
                }
                .padding(ReasiSpacing.s5)
            }
            .background(Color.reasi.background.ignoresSafeArea())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingDetailsSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
            HStack(spacing: ReasiSpacing.s5) {
                Button {
                    Task { await restore() }
                } label: {
                    if revenueCat.isRestoring {
                        ProgressView().tint(Color.reasi.text)
                    } else {
                        Text("Restore")
                    }
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.text)
                .disabled(revenueCat.isPurchasing || revenueCat.isRestoring || isRefreshingAccess)
                .accessibilityLabel("Restore Purchases")

                Menu {
                    Button("Why Reasi Pro?") {
                        showingDetailsSheet = true
                    }
                    legalLinks
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.reasi.textMuted)
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel("More paywall details")
            }

            Text("Subscriptions are managed through your Apple ID.")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
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
