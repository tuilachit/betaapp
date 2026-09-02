import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(RevenueCatService.self) private var revenueCat
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(SpendingStore.self) private var spending

    @State private var email = ""
    @State private var password = ""
    @State private var authMessage: String?
    @State private var authIsBusy = false
    @State private var showDeleteConfirmation = false
    @State private var activeSettingsDestination: ProfileSettingsDestination?
    @State private var appleRawNonce: String?
    @State private var preferenceSyncMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                header
                if supabase.isSignedIn {
                    signedInAccountCard
                    subscriptionSection
                } else {
                    authCard
                }
                planPreferencesSection
                shoppingSettingsSection
                supportSection
                if supabase.isSignedIn {
                    accountActionsSection
                }
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, 120)
        }
        .background(Color.reasi.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "Delete your Reasi account?",
            isPresented: $showDeleteConfirmation,
        ) {
            Button("Delete account", role: .destructive) {
                runAuthAction(mode: .deleteAccount)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Reasi data and subscription profile. It does not cancel billing through Apple; manage or cancel an active App Store subscription separately before deleting.")
        }
        .sheet(item: $activeSettingsDestination) { destination in
            switch destination {
            case .planning:
                PlanningPreferencesSettingsView(
                    preferences: onboarding.preferences,
                    onSave: savePlanningPreferences
                )
            case .store:
                StoreSettingsView(selectedStore: appState.selectedStore, onSelect: selectStore)
            case .spending:
                SpendingPreferencesSettingsView(
                    preferences: onboarding.preferences,
                    onSave: saveSpendingPreferences
                )
            case .shopping:
                ShoppingPreferencesSettingsView()
            case .reminders:
                PlanningReminderSettingsView()
            }
        }
        .onAppear {
            supabase.refreshAuthLabel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)
                    .frame(width: 44, height: 44)
                    .background(Color.reasi.surface, in: Circle())
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text("Profile")
                    .font(ReasiTypography.largeTitle)
                    .foregroundStyle(Color.reasi.text)
                Text(supabase.isSignedIn ? "Your account and preferences" : "Sign in to keep your plans in sync")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack(alignment: .top, spacing: ReasiSpacing.s4) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(accountStatusText)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                }

                Spacer()
            }

            signedOutControls

            if authIsBusy {
                HStack(spacing: ReasiSpacing.s3) {
                    ProgressView()
                        .tint(Color.reasi.text)
                    Text("Working securely...")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if let authMessage {
                Text(authMessage)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(isErrorMessage(authMessage) ? Color.reasi.danger : Color.reasi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    private var signedOutControls: some View {
        VStack(spacing: ReasiSpacing.s3) {
            if supabase.hasPendingEmailVerification {
                pendingEmailVerificationNotice
            }

            if supabase.config.appleAuthEnabled {
                SignInWithAppleButton(.signIn) { request in
                    prepareAppleRequest(request)
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .clipShape(Capsule())
                .disabled(authIsBusy || !supabase.config.hasSupabase)
                .opacity(authIsBusy || !supabase.config.hasSupabase ? 0.62 : 1)
                .accessibilityLabel("Sign in with Apple")
            }

            Button {
                runGoogleSignIn()
            } label: {
                HStack(spacing: ReasiSpacing.s3) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Continue with Google")
                        .font(ReasiTypography.bodyMedium)
                }
                .foregroundStyle(Color.reasi.text)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.reasi.surfaceHigh, in: Capsule())
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(authIsBusy || !supabase.config.hasSupabase || supabase.config.googleClientID.isEmpty)
            .opacity(authIsBusy || !supabase.config.hasSupabase || supabase.config.googleClientID.isEmpty ? 0.62 : 1)

            HStack(spacing: ReasiSpacing.s3) {
                Rectangle()
                    .fill(Color.reasi.border)
                    .frame(height: 1)
                Text("or use email")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .fixedSize()
                Rectangle()
                    .fill(Color.reasi.border)
                    .frame(height: 1)
            }

            VStack(spacing: ReasiSpacing.s3) {
                authField("Email", text: $email, symbol: "envelope", keyboardType: .emailAddress)
                passwordField
            }

            HStack(spacing: ReasiSpacing.s3) {
                secondaryAuthButton("Sign in", symbol: "arrow.right.circle") {
                    runAuthAction(mode: .signIn)
                }

                secondaryAuthButton("Create account", symbol: "plus.circle") {
                    runAuthAction(mode: .signUp)
                }
            }

            secondaryAuthButton("Forgot password", symbol: "key") {
                runAuthAction(mode: .resetPassword)
            }

            #if DEBUG
            if supabase.config.debugGuestAuthEnabled {
                Button {
                    runAuthAction(mode: .guest)
                } label: {
                    Label("Continue for testing", systemImage: "ladybug")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ReasiSpacing.s3)
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(authIsBusy || !supabase.config.hasSupabase)
            }
            #endif
        }
    }

    private var pendingEmailVerificationNotice: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.reasi.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verify your email")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text("We sent a confirmation link to \(supabase.currentUserEmail ?? "your email"). Open it on this iPhone, then sign in with your password.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: ReasiSpacing.s3) {
                secondaryAuthButton("Resend", symbol: "paperplane") {
                    runAuthAction(mode: .resendVerification)
                }

                secondaryAuthButton("I verified", symbol: "checkmark.circle") {
                    runAuthAction(mode: .signIn)
                }
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var signedInAccountCard: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack(spacing: ReasiSpacing.s3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.reasi.success)

                VStack(alignment: .leading, spacing: 3) {
                    Text(accountIdentityTitle)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                        .lineLimit(1)
                    Text(authMethodLabel)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }

                Spacer()
            }

            if supabase.currentAuthMethod == .email && !supabase.emailIsVerified {
                HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color.reasi.warning)
                    Text("Email is not verified yet. Verify it before generating a plan or using live shopping tools.")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))

                secondaryAuthButton("Resend verification", symbol: "envelope.badge") {
                    runAuthAction(mode: .resendVerification)
                }
            }

            if authIsBusy {
                HStack(spacing: ReasiSpacing.s3) {
                    ProgressView()
                        .tint(Color.reasi.text)
                    Text("Updating your account")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            }

            if let authMessage {
                Text(authMessage)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(isErrorMessage(authMessage) ? Color.reasi.danger : Color.reasi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private var planPreferencesSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionTitle("Personalization")

            VStack(spacing: 1) {
                Button {
                    ReasiHaptics.light()
                    activeSettingsDestination = .planning
                } label: {
                    profileRow(
                        "Meal planning",
                        value: planningProfileSummary,
                        subtitle: "Goal, household and food preferences",
                        symbol: "slider.horizontal.3",
                        accessory: .chevron
                    )
                }
                .buttonStyle(ReasiPressStyle())

                Button {
                    ReasiHaptics.light()
                    activeSettingsDestination = .store
                } label: {
                    profileRow(
                        "Preferred store",
                        value: appState.selectedStore.name,
                        subtitle: "Sets the aisle route for future lists",
                        symbol: "storefront",
                        accessory: .chevron
                    )
                }
                .buttonStyle(ReasiPressStyle())

                Button {
                    ReasiHaptics.light()
                    activeSettingsDestination = .spending
                } label: {
                    profileRow(
                        "Spending coach",
                        value: onboarding.preferences.spendingCoachTone.title,
                        subtitle: spendingPreferenceSummary,
                        symbol: "chart.bar",
                        accessory: .chevron
                    )
                }
                .buttonStyle(ReasiPressStyle())
            }
            .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }

            if let preferenceSyncMessage {
                Label(preferenceSyncMessage, systemImage: "icloud.slash")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var shoppingSettingsSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionTitle("Shopping & app")

            VStack(spacing: 1) {
                Button {
                    ReasiHaptics.light()
                    activeSettingsDestination = .shopping
                } label: {
                    profileRow(
                        "List behavior",
                        value: userSettings.shoppingBehaviorSummary,
                        subtitle: "Bought items and screen behavior",
                        symbol: "checklist",
                        accessory: .chevron
                    )
                }
                .buttonStyle(ReasiPressStyle())

                Button {
                    ReasiHaptics.light()
                    activeSettingsDestination = .reminders
                } label: {
                    profileRow(
                        "Weekly reminder",
                        value: userSettings.reminderSummary,
                        subtitle: "A gentle nudge to plan before the week",
                        symbol: "bell",
                        accessory: .chevron
                    )
                }
                .buttonStyle(ReasiPressStyle())

                Toggle(
                    isOn: Binding(
                        get: { userSettings.hapticsEnabled },
                        set: { enabled in updateHaptics(enabled) }
                    )
                ) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Haptic feedback")
                                .font(ReasiTypography.bodyMedium)
                                .foregroundStyle(Color.reasi.text)
                            Text("Tactile taps while planning and shopping")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                        }
                    } icon: {
                        Image(systemName: "hand.tap")
                            .frame(width: 22)
                            .foregroundStyle(Color.reasi.muted)
                    }
                }
                .tint(Color.reasi.text)
                .padding(ReasiSpacing.s4)
                .frame(minHeight: 64)
                .background(Color.reasi.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionTitle("Support & privacy")

            VStack(spacing: 1) {
                privacyPolicyRow
                termsOfServiceRow
                profileRow("App version", value: appVersion, symbol: "info.circle")
            }
            .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
    }

    private var subscriptionSection: some View {
        let presentation = subscriptionPresentation
        return VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionTitle("Plan access")

            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                HStack(spacing: ReasiSpacing.s4) {
                    Image(systemName: presentation.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: 40, height: 40)
                        .background(Color.reasi.surfaceHigh, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.title)
                            .font(ReasiTypography.bodyMedium)
                            .foregroundStyle(Color.reasi.text)
                        Text(presentation.detail)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                    }

                    Spacer()

                    if revenueCat.isLoading {
                        ProgressView().tint(Color.reasi.textMuted)
                    }
                }

                if revenueCat.isReasiProActive || revenueCat.serverAccess?.isPro == true {
                    Link(destination: revenueCat.managementURLWithFallback) {
                        Label("Manage subscription", systemImage: "arrow.up.right")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.text)
                    }
                }
            }
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
    }

    private var accountActionsSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionTitle("Account")

            VStack(spacing: 1) {
                Button {
                    runAuthAction(mode: .signOut)
                } label: {
                    profileRow(
                        "Sign out",
                        symbol: "rectangle.portrait.and.arrow.right"
                    )
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(authIsBusy)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: ReasiSpacing.s4) {
                        Image(systemName: "trash")
                            .frame(width: 22)
                            .foregroundStyle(Color.reasi.danger)
                        Text("Delete account")
                            .font(ReasiTypography.bodyMedium)
                            .foregroundStyle(Color.reasi.danger)
                        Spacer()
                    }
                    .padding(ReasiSpacing.s4)
                    .frame(minHeight: 54)
                    .background(Color.reasi.surface)
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(authIsBusy)
            }
            .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)
            .textCase(.uppercase)
            .padding(.leading, ReasiSpacing.s1)
    }

    private var foodStylesSummary: String {
        let titles = onboarding.preferences.foodStyles
            .map(\.title)
            .sorted()
        guard !titles.isEmpty else { return "Not set" }
        if titles.count <= 2 { return titles.joined(separator: ", ") }
        return "\(titles.prefix(2).joined(separator: ", ")) +\(titles.count - 2)"
    }

    private var planningProfileSummary: String {
        let household = onboarding.preferences.household?.title ?? "Two"
        return "\(onboarding.preferences.purposeSummary) · \(household)"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var authMethodLabel: String {
        switch supabase.currentAuthMethod {
        case .apple:
            supabase.currentUserUsesApplePrivateRelay ? "Apple · Private email" : "Apple"
        case .google:
            "Google"
        case .email:
            supabase.emailIsVerified ? "Email verified" : "Email verification needed"
        case .anonymous:
            "Development session"
        case .unknown, .none:
            "Signed in"
        }
    }

    private var accountIdentityTitle: String {
        if let email = supabase.currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        return supabase.currentAuthMethod == .anonymous ? "Test account" : "Reasi account"
    }

    private func selectStore(_ store: StoreSummary) {
        let displayedStoreId = coreLoop.hasPlan ? coreLoop.plan.shoppingList.storeId : appState.selectedStore.id
        guard store.id != displayedStoreId || store.id != appState.selectedStore.id else { return }
        preferenceSyncMessage = nil
        analytics.capture(.storeSelected, properties: [
            "store_id": .string(store.id.rawValue),
            "store_name": .string(store.name),
            "source": .string("profile")
        ])

        coreLoop.requestStoreSwitch(
            to: store,
            appState: appState,
            supabase: supabase,
            analytics: analytics,
            completion: { succeeded, confirmedStore in
                onboarding.applyConfirmedStore(confirmedStore)
                if !succeeded {
                    preferenceSyncMessage = "Your previous store is still selected. Try again when you're online."
                }
            }
        )
    }

    private func savePlanningPreferences(_ preferences: OnboardingPreferences) async {
        onboarding.updateProfilePreferences(preferences)
        preferenceSyncMessage = nil
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("planning_preferences"),
            "purpose": .string(preferences.primaryPurpose?.rawValue ?? "not_set"),
            "purpose_tags": .stringArray(preferences.selectedPurposes.map(\.rawValue)),
            "purpose_count": .int(preferences.selectedPurposes.count),
            "household": .string(preferences.household?.rawValue ?? "not_set"),
            "food_style_count": .int(preferences.foodStyles.count)
        ])

        guard supabase.isSignedIn else { return }
        do {
            try await supabase.saveOnboardingPreferences(preferences)
            onboarding.markPreferencesSynced()
            ReasiHaptics.success()
        } catch {
            preferenceSyncMessage = "Saved on this iPhone. Preference sync will retry when you're online."
            ReasiHaptics.warning()
        }
    }

    private func saveSpendingPreferences(_ preferences: OnboardingPreferences) async {
        let previousBudget = onboarding.preferences.weeklyGroceryBudgetAud
        onboarding.updateProfilePreferences(preferences)
        preferenceSyncMessage = nil

        guard supabase.isSignedIn else { return }
        do {
            try await supabase.saveSpendingPreferences(
                weeklyBudgetAud: preferences.weeklyGroceryBudgetAud,
                coachTone: preferences.spendingCoachTone
            )
            onboarding.markPreferencesSynced()
            analytics.capture(.settingsUpdated, properties: [
                "setting": .string("spending_preferences"),
                "coach_tone": .string(preferences.spendingCoachTone.rawValue),
                "has_budget": .bool(preferences.weeklyGroceryBudgetAud != nil)
            ])
            if previousBudget != preferences.weeklyGroceryBudgetAud {
                analytics.capture(.weeklyBudgetSet, properties: [
                    "has_budget": .bool(preferences.weeklyGroceryBudgetAud != nil),
                    "source": .string("profile")
                ])
            }
            await spending.refresh(supabase: supabase)
            ReasiHaptics.success()
        } catch {
            preferenceSyncMessage = "Saved on this iPhone. Preference sync will retry when you're online."
            ReasiHaptics.warning()
        }
    }

    private var spendingPreferenceSummary: String {
        guard let budget = onboarding.preferences.weeklyGroceryBudgetAud else {
            return "Tone and optional weekly target"
        }
        return "\(budget.formatted(.currency(code: "AUD"))) weekly target"
    }

    private func updateHaptics(_ enabled: Bool) {
        userSettings.setHapticsEnabled(enabled)
        if enabled { ReasiHaptics.selection() }
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("haptics"),
            "enabled": .bool(enabled)
        ])
    }

    @ViewBuilder
    private var privacyPolicyRow: some View {
        if let privacyPolicyURL = supabase.config.privacyPolicyURL {
            Link(destination: privacyPolicyURL) {
                profileRow("Privacy policy", symbol: "hand.raised", accessory: .externalLink)
            }
        } else {
            profileRow("Privacy policy", value: "Unavailable", symbol: "hand.raised")
        }
    }

    @ViewBuilder
    private var termsOfServiceRow: some View {
        if let termsURL = supabase.config.termsOfServiceURL {
            Link(destination: termsURL) {
                profileRow("Terms of use", symbol: "doc.text", accessory: .externalLink)
            }
        } else {
            profileRow("Terms of use", value: "Unavailable", symbol: "doc.text")
        }
    }

    private var subscriptionPresentation: (title: String, detail: String, symbol: String) {
        if revenueCat.serverAccess?.isPro == true {
            return ("Reasi Pro", "Unlimited week planning is active.", "sparkles")
        }
        if revenueCat.isReasiProActive || revenueCat.accessRefreshPending {
            return ("Reasi Pro", "Purchase found. Updating your plan access.", "arrow.triangle.2.circlepath")
        }
        switch revenueCat.serverAccess?.freePreviewStatus {
        case .available:
            return ("Free preview", "Your first complete week is ready when you are.", "calendar.badge.checkmark")
        case .reserved:
            return ("Planning preview", "Your included week is being prepared.", "clock")
        case .completed:
            return ("Free preview used", "Your saved plan and shopping list remain available.", "checkmark.circle")
        case nil:
            return ("Plan access", "Access status will refresh when you're connected.", "wifi.exclamationmark")
        }
    }

    private var passwordField: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Image(systemName: "lock")
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.text)
                .tint(Color.reasi.text)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var accountStatusText: String {
        if !supabase.config.hasSupabase {
            return "Sign-in is temporarily unavailable."
        }

        var methods: [String] = []
        if supabase.config.appleAuthEnabled {
            methods.append("Apple")
        }
        if !supabase.config.googleClientID.isEmpty {
            methods.append("Google")
        }
        methods.append("email")

        switch methods.count {
        case 1:
            return "Continue with \(methods[0])."
        case 2:
            return "Continue with \(methods[0]) or \(methods[1])."
        default:
            return "Continue with \(methods.dropLast().joined(separator: ", ")), or \(methods.last!)."
        }
    }

    private func authField(
        _ placeholder: String,
        text: Binding<String>,
        symbol: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: ReasiSpacing.s3) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .textContentType(.emailAddress)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.text)
                .tint(Color.reasi.text)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private func secondaryAuthButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ReasiSpacing.s4)
                .background(Color.reasi.surfaceHigh, in: Capsule())
        }
        .buttonStyle(ReasiPressStyle())
        .disabled(authIsBusy || !supabase.config.hasSupabase)
        .opacity(authIsBusy || !supabase.config.hasSupabase ? 0.62 : 1)
    }

    private enum ProfileRowAccessory {
        case none
        case chevron
        case externalLink

        var symbol: String? {
            switch self {
            case .none: nil
            case .chevron: "chevron.right"
            case .externalLink: "arrow.up.right"
            }
        }
    }

    private func profileRow(
        _ title: String,
        value: String? = nil,
        subtitle: String? = nil,
        symbol: String,
        accessory: ProfileRowAccessory = .none
    ) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                if let subtitle {
                    Text(subtitle)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            if let accessorySymbol = accessory.symbol {
                Image(systemName: accessorySymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.reasi.dim)
            }
        }
        .padding(ReasiSpacing.s4)
        .frame(minHeight: subtitle == nil ? 54 : 66)
        .background(Color.reasi.surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "")
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            appleRawNonce = nil
            if supabase.isAuthCancellation(error) {
                authMessage = nil
                ReasiHaptics.selection()
            } else {
                authMessage = supabase.userFacingMessage(for: error)
                ReasiHaptics.warning()
            }

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = appleRawNonce
            else {
                appleRawNonce = nil
                authMessage = "Apple did not return a valid identity token. Please try again."
                ReasiHaptics.warning()
                return
            }
            appleRawNonce = nil

            runAuthAction(
                mode: .apple(
                    idToken: idToken,
                    nonce: rawNonce,
                    profile: AppleIdentityProfile(components: credential.fullName)
                )
            )
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let rawNonce = try randomNonce()
            appleRawNonce = rawNonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = sha256(rawNonce)
        } catch {
            appleRawNonce = nil
            authMessage = "Apple sign-in could not start securely. Please try again."
            ReasiHaptics.warning()
        }
    }

    private func runGoogleSignIn() {
        #if canImport(GoogleSignIn)
        guard !supabase.config.googleClientID.isEmpty else {
            authMessage = "Google sign-in isn't available right now. Use email instead."
            ReasiHaptics.warning()
            return
        }

        guard let rootViewController = UIApplication.shared.reasiRootViewController else {
            authMessage = "Google sign-in couldn't open. Please try again."
            ReasiHaptics.warning()
            return
        }

        authIsBusy = true
        authMessage = nil
        ReasiHaptics.light()
        analytics.capture(.authSignInStarted, properties: ["method": .string(AuthMethod.google.rawValue)])

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: supabase.config.googleClientID)

        Task {
            do {
                let nonce = try randomNonce()
                let hashedNonce = sha256(nonce)
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootViewController,
                    hint: nil,
                    additionalScopes: nil,
                    nonce: hashedNonce
                )
                guard let idToken = result.user.idToken?.tokenString else {
                    throw ProfileAuthError.missingGoogleIDToken
                }

                try await supabase.signInWithGoogle(
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    nonce: nonce
                )
                captureSuccessfulAuth(method: .google, signedUp: false)
                authMessage = "Signed in with Google."
                ReasiHaptics.success()
            } catch {
                if supabase.isAuthCancellation(error) {
                    authMessage = nil
                    ReasiHaptics.selection()
                } else {
                    authMessage = authFailureMessage(for: error)
                    ReasiHaptics.warning()
                }
            }

            authIsBusy = false
        }
        #else
        authMessage = "Google sign-in isn't available right now. Use email instead."
        ReasiHaptics.warning()
        #endif
    }

    private func randomNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let maxValidByte = UInt8.max - UInt8.max % UInt8(charset.count)
        var result = ""

        while result.count < length {
            var randomByte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte)
            guard status == errSecSuccess else {
                throw ProfileAuthError.nonceGenerationFailed
            }

            guard randomByte < maxValidByte else { continue }
            result.append(charset[Int(randomByte) % charset.count])
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private func runAuthAction(mode: AuthActionMode) {
        guard !authIsBusy else { return }

        authIsBusy = true
        authMessage = nil
        ReasiHaptics.light()

        Task {
            do {
                switch mode {
                case .apple(let idToken, let nonce, let profile):
                    analytics.capture(.authSignInStarted, properties: ["method": .string(AuthMethod.apple.rawValue)])
                    let outcome = try await supabase.signInWithApple(
                        idToken: idToken,
                        nonce: nonce,
                        profile: profile
                    )
                    captureSuccessfulAuth(method: .apple, signedUp: outcome.isNewUser)
                    authMessage = outcome.usesPrivateRelayEmail
                        ? "Signed in with Apple. Your email stays private."
                        : "Signed in with Apple."
                    ReasiHaptics.success()

                case .signIn:
                    try validateEmailAndPassword()
                    analytics.capture(.authSignInStarted, properties: ["method": .string(AuthMethod.email.rawValue)])
                    try await supabase.signIn(email: trimmedEmailOrCurrentEmail, password: password)
                    captureSuccessfulAuth(method: .email, signedUp: false)
                    authMessage = supabase.emailIsVerified
                        ? "You're signed in."
                        : "You're signed in. Verify your email before using live planning tools."
                    ReasiHaptics.success()

                case .signUp:
                    try validateNewEmailAndPassword()
                    analytics.capture(.authSignInStarted, properties: ["method": .string("email_signup")])
                    try await supabase.signUp(email: trimmedEmail, password: password)
                    if supabase.isSignedIn {
                        captureSuccessfulAuth(method: .email, signedUp: true)
                        authMessage = "Account created. You're signed in."
                    } else {
                        capturePendingEmailSignUp()
                        authMessage = "Account created. Check your email, tap the verification link, then sign in here."
                    }
                    ReasiHaptics.success()

                case .resendVerification:
                    try validateEmail()
                    try await supabase.resendEmailVerification(email: trimmedEmailOrCurrentEmail)
                    authMessage = "Verification email sent."
                    ReasiHaptics.success()

                case .resetPassword:
                    try validateEmail()
                    try await supabase.sendPasswordReset(email: trimmedEmailOrCurrentEmail)
                    analytics.capture(.authPasswordResetRequested, properties: ["method": .string(AuthMethod.email.rawValue)])
                    authMessage = "Password reset email sent."
                    ReasiHaptics.success()

                case .signOut:
                    try await supabase.signOut()
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.signOut()
                    #endif
                    coreLoop.activateUser(nil, selectedStore: appState.selectedStore)
                    analytics.resetIdentity()
                    authMessage = "Signed out."
                    ReasiHaptics.selection()

                case .deleteAccount:
                    let deletedUserId = supabase.currentUserId
                    analytics.capture(.accountDeletionStarted)
                    try await supabase.deleteAccount()
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.signOut()
                    #endif
                    if deletedUserId != nil {
                        coreLoop.activateUser(nil, selectedStore: appState.selectedStore)
                    }
                    analytics.capture(.accountDeletionCompleted)
                    analytics.resetIdentity()
                    authMessage = "Account deleted."
                    ReasiHaptics.success()

                #if DEBUG
                case .guest:
                    analytics.capture(.authSignInStarted, properties: ["method": .string(AuthMethod.anonymous.rawValue)])
                    try await supabase.signInAnonymously()
                    captureSuccessfulAuth(method: .anonymous, signedUp: false)
                    authMessage = "Testing access is ready."
                    ReasiHaptics.success()
                #endif
                }
            } catch {
                if case .deleteAccount = mode {
                    analytics.capture(.accountDeletionFailed, properties: ["error": .string(error.localizedDescription)])
                }
                if supabase.isAuthCancellation(error) {
                    authMessage = nil
                    ReasiHaptics.selection()
                } else {
                    authMessage = authFailureMessage(for: error)
                    ReasiHaptics.warning()
                }
            }

            authIsBusy = false
        }
    }

    private func captureSuccessfulAuth(method: AuthMethod, signedUp: Bool) {
        let properties: [String: AnalyticsProperty] = ["method": .string(method.rawValue)]
        analytics.capture(.authSignInCompleted, properties: properties)
        analytics.capture(signedUp ? .signUp : .signIn, properties: properties)

        if let userId = supabase.currentUserId {
            var identifyProperties: [String: AnalyticsProperty] = [
                "auth_method": .string(method.rawValue),
                "email_verified": .bool(supabase.emailIsVerified)
            ]
            if let email = supabase.currentUserEmail {
                identifyProperties["has_email"] = .bool(!email.isEmpty)
            }
            if method == .apple {
                identifyProperties["apple_private_relay"] = .bool(supabase.currentUserUsesApplePrivateRelay)
            }
            analytics.identify(userId: userId, properties: identifyProperties)
        }
    }

    private func capturePendingEmailSignUp() {
        analytics.capture(.signUp, properties: [
            "method": .string(AuthMethod.email.rawValue),
            "email_verification_required": .bool(true)
        ])
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmailOrCurrentEmail: String {
        let candidate = trimmedEmail
        if !candidate.isEmpty { return candidate }
        return supabase.currentUserEmail ?? ""
    }

    private func validateEmailAndPassword() throws {
        try validateEmail()
        if password.count < 6 {
            throw ProfileAuthError.passwordTooShort
        }
    }

    private func validateNewEmailAndPassword() throws {
        if trimmedEmail.isEmpty {
            throw ProfileAuthError.missingEmail
        }
        if password.count < 6 {
            throw ProfileAuthError.passwordTooShort
        }
    }

    private func validateEmail() throws {
        if trimmedEmailOrCurrentEmail.isEmpty {
            throw ProfileAuthError.missingEmail
        }
    }

    private func authFailureMessage(for error: Error) -> String {
        supabase.userFacingMessage(
            for: error,
            fallback: "Sign-in could not finish. Please try again."
        )
    }

    private func isErrorMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("failed") || lowercased.contains("missing") || lowercased.contains("could not")
    }
}

private enum AuthActionMode {
    case apple(idToken: String, nonce: String, profile: AppleIdentityProfile?)
    case signIn
    case signUp
    case resendVerification
    case resetPassword
    case signOut
    case deleteAccount

    #if DEBUG
    case guest
    #endif
}

private enum ProfileAuthError: LocalizedError {
    case missingGoogleIDToken
    case missingEmail
    case nonceGenerationFailed
    case passwordTooShort

    var errorDescription: String? {
        switch self {
        case .missingGoogleIDToken:
            "Google sign-in couldn't finish. Please try again."
        case .missingEmail:
            "Enter your email first."
        case .nonceGenerationFailed:
            "Could not start secure sign-in. Please try again."
        case .passwordTooShort:
            "Password must be at least 6 characters."
        }
    }
}

private extension UIApplication {
    var reasiRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

#Preview {
    ProfileView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(OnboardingStore())
        .environment(UserSettingsStore())
        .preferredColorScheme(.dark)
}
