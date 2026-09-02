import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct OnboardingPlaceholderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    @State private var email = ""
    @State private var password = ""
    @State private var emailMode: EmailAuthMode = .signIn
    @State private var showsEmailForm = false
    @State private var authIsBusy = false
    @State private var authMessage: String?
    @State private var appleRawNonce: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                screenContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ReasiSpacing.s5)
                    .padding(.bottom, ReasiSpacing.s5)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, ReasiSpacing.s5)
        .safeAreaPadding(.top, ReasiSpacing.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAction
                .transaction { transaction in
                    transaction.animation = nil
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s3)
                .padding(.bottom, ReasiSpacing.s4)
                .background(Color.reasi.background)
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .animation(ReasiMotion.slow, value: onboarding.currentStep)
        .onAppear {
            onboarding.captureStartedIfNeeded(analytics: analytics)
        }
    }

    private var topBar: some View {
        HStack(spacing: ReasiSpacing.s4) {
            if onboarding.currentStep.rawValue >= OnboardingStep.purpose.rawValue {
                HStack(spacing: ReasiSpacing.s1) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(
                                index <= onboarding.currentStep.progressIndex
                                    ? Color.reasi.text
                                    : Color.reasi.border
                            )
                            .frame(height: 3)
                    }
                }
                .accessibilityLabel("Onboarding progress")
            } else {
                Text("Reasi")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
            }

            Spacer(minLength: ReasiSpacing.s3)

            if onboarding.currentStep.isSurvey {
                Button("Skip") {
                    onboarding.skipCurrentSurvey(analytics: analytics)
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .buttonStyle(ReasiPressStyle())
                .accessibilityHint("Skips this question")
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var screenContent: some View {
        Group {
            switch onboarding.currentStep {
            case .value:
                valueScreen
            case .benefit:
                benefitScreen
            case .purpose:
                purposeScreen
            case .household:
                householdScreen
            case .foodStyle:
                foodStyleScreen
            case .spendingTone:
                spendingToneScreen
            case .store:
                storeScreen
            case .signIn:
                signInScreen
            case .ready:
                readyScreen
            }
        }
        .id(onboarding.currentStep)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity.combined(with: .offset(x: -18))
            )
        )
    }

    private var valueScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            Spacer(minLength: 54)

            Circle()
                .fill(Color.reasi.surface)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.reasi.text)
                }
                .overlay {
                    Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                }

            Text("Never think about\ngroceries again.")
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("A useful week of meals and one calm list, ready when you are.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 80)
        }
        .frame(minHeight: 540, alignment: .topLeading)
    }

    private var benefitScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
            onboardingHeading(
                eyebrow: "A calmer weekly shop",
                title: "Plan your week, build your list, and shop smarter in minutes."
            )

            VStack(spacing: ReasiSpacing.s3) {
                benefitRow(symbol: "calendar", title: "Seven dinners", detail: "Practical meals you can actually cook")
                benefitRow(symbol: "checklist", title: "One smart list", detail: "Ingredients consolidated for the week")
                benefitRow(symbol: "storefront", title: "Your store order", detail: "Grouped around the way you walk the shop")
            }
        }
    }

    private var purposeScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            onboardingHeading(
                eyebrow: "Shape your week",
                title: "What makes groceries hardest?"
            )

            HStack {
                Text(purposeSelectionGuidance)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)

                Spacer(minLength: ReasiSpacing.s3)

                Text("\(onboarding.preferences.selectedPurposes.count)/\(OnboardingPreferences.maximumPurposeSelections)")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.text)
                    .padding(.horizontal, ReasiSpacing.s3)
                    .padding(.vertical, ReasiSpacing.s1)
                    .background(Color.reasi.surfaceHigh, in: Capsule())
            }

            VStack(spacing: ReasiSpacing.s2) {
                ForEach(OnboardingPurpose.allCases) { purpose in
                    let selectedPurposes = onboarding.preferences.selectedPurposes
                    let rank = selectedPurposes.firstIndex(of: purpose).map { $0 + 1 }
                    purposeSelectionCard(
                        title: purpose.title,
                        detail: purpose.summary,
                        symbol: purpose.symbol,
                        rank: rank,
                        isAtSelectionLimit: selectedPurposes.count == OnboardingPreferences.maximumPurposeSelections
                    ) {
                        withAnimation(reduceMotion ? nil : ReasiMotion.tactileSpring) {
                            onboarding.togglePurpose(purpose)
                        }
                    }
                }
            }
        }
    }

    private var householdScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Serving size",
                title: "How many are you cooking for?"
            )

            VStack(spacing: ReasiSpacing.s3) {
                ForEach(HouseholdChoice.allCases) { choice in
                    selectionCard(
                        title: choice.title,
                        detail: "Recipes and quantities for \(choice.householdSize)",
                        symbol: choice.householdSize == 1 ? "person" : "person.2",
                        isSelected: onboarding.preferences.household == choice
                    ) {
                        onboarding.preferences.household = choice
                        ReasiHaptics.selection()
                    }
                }
            }
        }
    }

    private var foodStyleScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Choose any that fit",
                title: "What feels good to cook?"
            )

            OnboardingChipLayout(spacing: ReasiSpacing.s2) {
                ForEach(FoodStyle.allCases) { style in
                    let isSelected = onboarding.preferences.foodStyles.contains(style)
                    Button {
                        onboarding.toggleFoodStyle(style)
                    } label: {
                        HStack(spacing: ReasiSpacing.s2) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(style.title)
                                .font(ReasiTypography.bodyMedium)
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? Color.reasi.background : Color.reasi.textMuted)
                        .padding(.horizontal, ReasiSpacing.s4)
                        .frame(height: 48)
                        .background(
                            isSelected ? Color.reasi.text : Color.reasi.surface,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(isSelected ? Color.clear : Color.reasi.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }

            Text("Pick a mix. Your plan can still vary from week to week.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
        }
    }

    private var spendingToneScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Your spending coach",
                title: "How should Reasi talk about money?"
            )

            VStack(spacing: ReasiSpacing.s3) {
                ForEach(SpendingCoachTone.allCases) { tone in
                    selectionCard(
                        title: tone.title,
                        detail: tone.detail,
                        symbol: tone.symbolName,
                        isSelected: onboarding.preferences.spendingCoachTone == tone
                    ) {
                        onboarding.preferences.spendingCoachTone = tone
                        ReasiHaptics.selection()
                    }
                }
            }
        }
    }

    private var storeScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Your shopping route",
                title: "Where do you usually shop?"
            )

            VStack(spacing: ReasiSpacing.s3) {
                ForEach(FixtureStores.launchStores) { store in
                    Button {
                        guard onboarding.preferences.selectedStoreId != store.id else { return }
                        onboarding.selectStore(store)
                        analytics.capture(.storeSelected, properties: [
                            "store_id": .string(store.id.rawValue),
                            "store_name": .string(store.name),
                            "source": .string("onboarding")
                        ])
                    } label: {
                        HStack(spacing: ReasiSpacing.s4) {
                            Image(systemName: "storefront")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.reasi.text)
                                .frame(width: 42, height: 42)
                                .background(Color.reasi.surfaceHigh, in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.name)
                                    .font(ReasiTypography.headline)
                                    .foregroundStyle(Color.reasi.text)
                                Text(store.retailerDisplayName)
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.muted)
                            }

                            Spacer()

                            selectionIndicator(isSelected: onboarding.preferences.selectedStoreId == store.id)
                        }
                        .padding(ReasiSpacing.s4)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                                .stroke(
                                    onboarding.preferences.selectedStoreId == store.id
                                        ? Color.reasi.text
                                        : Color.reasi.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }
        }
    }

    private var signInScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Keep your plans with you",
                title: supabase.isSignedIn ? "You're signed in." : "Save your Reasi setup."
            )

            if supabase.isSignedIn {
                HStack(spacing: ReasiSpacing.s4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.reasi.background)
                        .frame(width: 44, height: 44)
                        .background(Color.reasi.text, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(supabase.authLabel)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                        Text("Your preferences will sync across devices.")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                    }
                }
                .padding(ReasiSpacing.s5)
                .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            } else {
                authControls
            }

            if let authMessage {
                Text(authMessage)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(authMessageIsError ? Color.reasi.danger : Color.reasi.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var authControls: some View {
        VStack(spacing: ReasiSpacing.s3) {
            if supabase.config.appleAuthEnabled {
                SignInWithAppleButton(.continue) { request in
                    prepareAppleRequest(request)
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .clipShape(Capsule())
                .disabled(authIsBusy)
                .accessibilityLabel("Continue with Apple")
            }

            authButton(title: "Continue with Google", symbol: "g.circle.fill") {
                runGoogleSignIn()
            }
            .disabled(authIsBusy || supabase.config.googleClientID.isEmpty)
            .opacity(supabase.config.googleClientID.isEmpty ? 0.55 : 1)

            authButton(title: showsEmailForm ? "Hide email" : "Continue with email", symbol: "envelope") {
                withAnimation(ReasiMotion.base) {
                    showsEmailForm.toggle()
                }
            }

            #if DEBUG
            if supabase.config.debugGuestAuthEnabled {
                authButton(title: "Continue for testing", symbol: "ladybug") {
                    runAuth(method: .anonymous) {
                        try await supabase.signInAnonymously()
                    }
                }
                .accessibilityHint("Available only in debug builds")
            }
            #endif

            if showsEmailForm {
                emailForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var emailForm: some View {
        VStack(spacing: ReasiSpacing.s3) {
            Picker("Email action", selection: $emailMode) {
                ForEach(EmailAuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .authFieldStyle()

            SecureField("Password", text: $password)
                .textContentType(emailMode == .signUp ? .newPassword : .password)
                .authFieldStyle()

            Button {
                runEmailAuth()
            } label: {
                HStack(spacing: ReasiSpacing.s2) {
                    if authIsBusy {
                        ProgressView().tint(Color.reasi.background)
                    }
                    Text(emailMode.actionTitle)
                }
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.reasi.text, in: Capsule())
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(authIsBusy)

            HStack {
                Button("Reset password") {
                    runEmailUtility(.resetPassword)
                }
                Spacer()
                Button("Resend verification") {
                    runEmailUtility(.resendVerification)
                }
            }
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.textMuted)
        }
        .padding(.top, ReasiSpacing.s2)
    }

    private var readyScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
            onboardingHeading(
                eyebrow: "Ready for your first week",
                title: "A plan shaped around you."
            )

            VStack(spacing: 0) {
                summaryRow(
                    symbol: onboarding.preferences.primaryPurpose?.symbol ?? "sparkles",
                    label: "Priorities",
                    value: purposeSummary
                )
                Divider().overlay(Color.reasi.border)
                summaryRow(
                    symbol: "person.2",
                    label: "Cooking for",
                    value: onboarding.preferences.household?.title ?? "Two (default)"
                )
                Divider().overlay(Color.reasi.border)
                summaryRow(
                    symbol: "fork.knife",
                    label: "Food style",
                    value: foodStyleSummary
                )
                Divider().overlay(Color.reasi.border)
                summaryRow(
                    symbol: onboarding.preferences.spendingCoachTone.symbolName,
                    label: "Spending coach",
                    value: onboarding.preferences.spendingCoachTone.title
                )
                Divider().overlay(Color.reasi.border)
                summaryRow(
                    symbol: "storefront",
                    label: "Store",
                    value: onboarding.preferences.selectedStoreId == nil
                        ? "Coles Top Ryde (default)"
                        : onboarding.preferences.resolvedStore.name
                )
            }
            .padding(.horizontal, ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))

            if let error = onboarding.errorMessage {
                Text(error)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bottomAction: some View {
        primaryButton(bottomActionTitle, enabled: bottomActionIsEnabled) {
            performBottomAction()
        }
    }

    private var bottomActionTitle: String {
        switch onboarding.currentStep {
        case .value:
            "Get started"
        case .benefit, .purpose, .household, .foodStyle, .spendingTone, .store:
            "Continue"
        case .signIn:
            supabase.isSignedIn ? "Continue" : "Sign in to continue"
        case .ready:
            onboarding.isSaving ? "Saving your choices" : "Plan my first week"
        }
    }

    private var bottomActionIsEnabled: Bool {
        switch onboarding.currentStep {
        case .value, .benefit:
            true
        case .purpose:
            !onboarding.preferences.selectedPurposes.isEmpty
        case .household:
            onboarding.preferences.household != nil
        case .foodStyle:
            !onboarding.preferences.foodStyles.isEmpty
        case .spendingTone:
            true
        case .store:
            onboarding.preferences.selectedStoreId != nil
        case .signIn:
            supabase.isSignedIn
        case .ready:
            !onboarding.isSaving
        }
    }

    private func performBottomAction() {
        switch onboarding.currentStep {
        case .value, .benefit, .household, .foodStyle, .spendingTone, .store, .signIn:
            onboarding.advance()
        case .purpose:
            onboarding.submitPurpose(analytics: analytics)
        case .ready:
            completeOnboarding()
        }
    }

    private func onboardingHeading(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text(eyebrow)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            Text(title)
                .font(ReasiTypography.title)
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func benefitRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 46, height: 46)
                .background(Color.reasi.surfaceHigh, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text(detail)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private func selectionCard(
        title: String,
        detail: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ReasiSpacing.s4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)
                    .frame(width: 42, height: 42)
                    .background(Color.reasi.surfaceHigh, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: ReasiSpacing.s2)
                selectionIndicator(isSelected: isSelected)
            }
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.reasi.text : Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
    }

    private func purposeSelectionCard(
        title: String,
        detail: String,
        symbol: String,
        rank: Int?,
        isAtSelectionLimit: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = rank != nil
        let isUnavailable = !isSelected && isAtSelectionLimit

        return Button(action: action) {
            HStack(spacing: ReasiSpacing.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)
                    .frame(width: 38, height: 38)
                    .background(Color.reasi.surfaceHigh, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: ReasiSpacing.s2)

                Circle()
                    .fill(isSelected ? Color.reasi.text : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle().stroke(
                            isSelected ? Color.reasi.text : Color.reasi.borderStrong,
                            lineWidth: 1.5
                        )
                    }
                    .overlay {
                        if let rank {
                            Text("\(rank)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.reasi.background)
                        }
                    }
            }
            .padding(.horizontal, ReasiSpacing.s4)
            .padding(.vertical, ReasiSpacing.s3)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.reasi.text : Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(
            rank.map { "Priority \($0)" }
                ?? (isUnavailable ? "Not selected. 3 priorities selected" : "Not selected")
        )
        .accessibilityHint(
            isSelected
                ? "Removes this priority so you can reorder your choices"
                : isUnavailable
                    ? "Remove a selected priority before adding this one"
                    : "Adds this as the next priority"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Circle()
            .fill(isSelected ? Color.reasi.text : Color.clear)
            .frame(width: 22, height: 22)
            .overlay {
                Circle().stroke(isSelected ? Color.reasi.text : Color.reasi.borderStrong, lineWidth: 1.5)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.reasi.background)
                }
            }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ReasiSpacing.s2) {
                if onboarding.isSaving {
                    ProgressView()
                        .tint(Color.reasi.background)
                        .controlSize(.small)
                }
                Text(title)
                    .lineLimit(1)
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private func authButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.reasi.surface, in: Capsule())
                .overlay { Capsule().stroke(Color.reasi.border, lineWidth: 1) }
        }
        .buttonStyle(ReasiPressStyle())
    }

    private func summaryRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 24)
            Text(label)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
            Spacer(minLength: ReasiSpacing.s3)
            Text(value)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, ReasiSpacing.s4)
    }

    private var foodStyleSummary: String {
        let labels = FoodStyle.allCases
            .filter { onboarding.preferences.foodStyles.contains($0) }
            .map(\.title)
        return labels.isEmpty ? "Surprise me" : labels.joined(separator: ", ")
    }

    private var purposeSummary: String {
        onboarding.preferences.purposeSummary
    }

    private var purposeSelectionGuidance: String {
        if onboarding.preferences.selectedPurposes.count == OnboardingPreferences.maximumPurposeSelections {
            return "3 selected. Tap one off to change your order."
        }
        return "Choose up to 3 in priority order."
    }

    private func completeOnboarding() {
        Task {
            let completed = await onboarding.complete(
                supabase: supabase,
                appState: appState,
                analytics: analytics
            )
            guard completed else { return }

            coreLoop.startWeekPlanGeneration(
                store: appState.selectedStore,
                supabase: supabase,
                analytics: analytics,
                appState: appState,
                network: network
            )
        }
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
                  let rawNonce = appleRawNonce else {
                appleRawNonce = nil
                authMessage = "Apple did not return a valid identity token. Please try again."
                ReasiHaptics.warning()
                return
            }
            appleRawNonce = nil

            runAppleSignIn(
                idToken: idToken,
                nonce: rawNonce,
                profile: AppleIdentityProfile(components: credential.fullName)
            )
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let rawNonce = try randomNonce()
            appleRawNonce = rawNonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = SHA256.hash(data: Data(rawNonce.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        } catch {
            appleRawNonce = nil
            authMessage = "Apple sign-in could not start securely. Please try again."
            ReasiHaptics.warning()
        }
    }

    private func runAppleSignIn(
        idToken: String,
        nonce: String,
        profile: AppleIdentityProfile?
    ) {
        guard !authIsBusy else { return }
        authIsBusy = true
        authMessage = nil
        ReasiHaptics.light()
        analytics.capture(.authSignInStarted, properties: [
            "method": .string(AuthMethod.apple.rawValue),
        ])

        Task {
            do {
                let outcome = try await supabase.signInWithApple(
                    idToken: idToken,
                    nonce: nonce,
                    profile: profile
                )
                finishSuccessfulAuth(method: .apple, signedUp: outcome.isNewUser)
            } catch {
                if supabase.isAuthCancellation(error) {
                    authMessage = nil
                    ReasiHaptics.selection()
                } else {
                    authMessage = authFailureMessage(error)
                    ReasiHaptics.warning()
                }
            }
            authIsBusy = false
        }
    }

    private func runGoogleSignIn() {
        #if canImport(GoogleSignIn)
        guard !supabase.config.googleClientID.isEmpty else {
            authMessage = "Google sign-in isn't available right now. Use email instead."
            return
        }
        guard let presenter = presentingViewController else {
            authMessage = "Google sign-in could not open. Please try again."
            return
        }

        runAuth(method: .google) {
            let nonce = try randomNonce()
            let hashedNonce = SHA256.hash(data: Data(nonce.utf8))
                .map { String(format: "%02x", $0) }
                .joined()

            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: supabase.config.googleClientID)
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw OnboardingAuthError.missingGoogleToken
            }
            try await supabase.signInWithGoogle(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                nonce: nonce
            )
        }
        #else
        authMessage = "Google sign-in is not available in this build."
        #endif
    }

    private func runEmailAuth() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            authMessage = "Enter your email first."
            return
        }
        guard password.count >= 6 else {
            authMessage = "Password must be at least 6 characters."
            return
        }

        switch emailMode {
        case .signIn:
            runAuth(method: .email) {
                try await supabase.signIn(email: cleanEmail, password: password)
                guard supabase.emailIsVerified else {
                    throw OnboardingAuthError.emailNotVerified
                }
            }
        case .signUp:
            guard !authIsBusy else { return }
            authIsBusy = true
            authMessage = nil
            analytics.capture(.authSignInStarted, properties: ["method": .string("email_signup")])

            Task {
                do {
                    try await supabase.signUp(email: cleanEmail, password: password)
                    if supabase.isSignedIn, supabase.emailIsVerified {
                        finishSuccessfulAuth(method: .email, signedUp: true)
                    } else {
                        analytics.capture(.signUp, properties: [
                            "method": .string(AuthMethod.email.rawValue),
                            "email_verification_required": .bool(true)
                        ])
                        authMessage = "Check your email, verify your address, then come back to sign in."
                        ReasiHaptics.success()
                    }
                } catch {
                    if supabase.isAuthCancellation(error) {
                        authMessage = nil
                        ReasiHaptics.selection()
                    } else {
                        authMessage = authFailureMessage(error)
                        ReasiHaptics.warning()
                    }
                }
                authIsBusy = false
            }
        }
    }

    private func runEmailUtility(_ utility: EmailUtility) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            authMessage = "Enter your email first."
            return
        }

        Task {
            do {
                switch utility {
                case .resetPassword:
                    try await supabase.sendPasswordReset(email: cleanEmail)
                    analytics.capture(.authPasswordResetRequested, properties: [
                        "method": .string(AuthMethod.email.rawValue)
                    ])
                    authMessage = "Password reset email sent."
                case .resendVerification:
                    try await supabase.resendEmailVerification(email: cleanEmail)
                    authMessage = "Verification email sent."
                }
                ReasiHaptics.success()
            } catch {
                if supabase.isAuthCancellation(error) {
                    authMessage = nil
                    ReasiHaptics.selection()
                } else {
                    authMessage = authFailureMessage(error)
                    ReasiHaptics.warning()
                }
            }
        }
    }

    private func runAuth(method: AuthMethod, operation: @escaping () async throws -> Void) {
        guard !authIsBusy else { return }
        authIsBusy = true
        authMessage = nil
        ReasiHaptics.light()
        analytics.capture(.authSignInStarted, properties: ["method": .string(method.rawValue)])

        Task {
            do {
                try await operation()
                finishSuccessfulAuth(method: method)
            } catch {
                if supabase.isAuthCancellation(error) {
                    authMessage = nil
                    ReasiHaptics.selection()
                } else {
                    authMessage = authFailureMessage(error)
                    ReasiHaptics.warning()
                }
            }
            authIsBusy = false
        }
    }

    private func finishSuccessfulAuth(method: AuthMethod, signedUp: Bool = false) {
        let properties: [String: AnalyticsProperty] = ["method": .string(method.rawValue)]
        analytics.capture(.authSignInCompleted, properties: properties)
        analytics.capture(signedUp ? .signUp : .signIn, properties: properties)
        if let userId = supabase.currentUserId {
            var identifyProperties: [String: AnalyticsProperty] = [
                "auth_method": .string(method.rawValue),
                "email_verified": .bool(supabase.emailIsVerified)
            ]
            if method == .apple {
                identifyProperties["apple_private_relay"] = .bool(supabase.currentUserUsesApplePrivateRelay)
            }
            analytics.identify(userId: userId, properties: identifyProperties)
        }
        authMessage = "Signed in. Your choices will be saved."
        ReasiHaptics.success()
        onboarding.advance()
    }

    private func authFailureMessage(_ error: Error) -> String {
        supabase.userFacingMessage(
            for: error,
            fallback: "Sign-in could not finish. Please try again."
        )
    }

    private var authMessageIsError: Bool {
        let value = authMessage?.lowercased() ?? ""
        return value.contains("failed") || value.contains("could not") || value.contains("must")
    }

    private var presentingViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    private func randomNonce(length: Int = 32) throws -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let maxValidByte = UInt8.max - UInt8.max % UInt8(characters.count)
        var result = ""

        while result.count < length {
            var randomByte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte) == errSecSuccess else {
                throw OnboardingAuthError.nonceGenerationFailed
            }
            guard randomByte < maxValidByte else { continue }
            result.append(characters[Int(randomByte) % characters.count])
        }
        return result
    }
}

private enum EmailAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }
    var title: String { self == .signIn ? "Sign in" : "Sign up" }
    var actionTitle: String { self == .signIn ? "Sign in" : "Create account" }
}

private enum EmailUtility {
    case resetPassword
    case resendVerification
}

private enum OnboardingAuthError: LocalizedError {
    case emailNotVerified
    case missingGoogleToken
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .emailNotVerified:
            "Email is not verified."
        case .missingGoogleToken:
            "Google sign-in couldn't finish. Please try again."
        case .nonceGenerationFailed:
            "Secure sign-in couldn't start. Please try again."
        }
    }
}

private struct OnboardingChipLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(in: proposal.width ?? 350, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(ReasiTypography.body)
            .foregroundStyle(Color.reasi.text)
            .padding(.horizontal, ReasiSpacing.s4)
            .frame(height: 52)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
    }
}

#Preview {
    OnboardingPlaceholderView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(OnboardingStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .preferredColorScheme(.dark)
}
