import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import PhotosUI
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct OnboardingPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var guidePhotoItem: PhotosPickerItem?
    @State private var guidePhotoData: Data?
    @State private var guideSubmission: StoreGuideSubmissionResponse?
    @State private var guideSections: [StoreGuideSection] = []
    @State private var guideError: String?
    @State private var guideIsBusy = false
    @State private var showGuideCamera = false

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
        .onChange(of: guidePhotoItem) { _, item in
            guard let item else { return }
            Task { await handleGuidePhoto(item) }
        }
        .fullScreenCover(isPresented: $showGuideCamera) {
            OnboardingCameraCaptureView { image in
                showGuideCamera = false
                guard let data = image.jpegData(compressionQuality: 0.86) else { return }
                Task { await processGuideData(data) }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: ReasiSpacing.s4) {
            if onboarding.currentStep.rawValue >= OnboardingStep.purpose.rawValue {
                HStack(spacing: ReasiSpacing.s1) {
                    ForEach(0..<OnboardingStep.progressStepCount, id: \.self) { index in
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
            } else if onboarding.currentStep == .storeGuide {
                Button("Skip") {
                    analytics.capture(.storeGuideSkipped, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue)])
                    onboarding.advance()
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .buttonStyle(ReasiPressStyle())
            }
        }
        .frame(minHeight: 36)
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
            case .budget:
                budgetScreen
            case .foodStyle:
                foodStyleScreen
            case .spendingTone:
                spendingToneScreen
            case .store:
                storeScreen
            case .signIn:
                signInScreen
            case .storeGuide:
                storeGuideScreen
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
        VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 0 : ReasiSpacing.s6)

            if !dynamicTypeSize.isAccessibilitySize {
                OnboardingReceiptPreview()
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                Text("Groceries that\nfit your budget.")
                    .font(ReasiTypography.font(size: 40, weight: .semibold, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(Color.reasi.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Dinners planned to your budget, one list, every dollar tracked.")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 560, alignment: .topLeading)
    }

    private var benefitScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
            onboardingHeading(
                eyebrow: "How it works",
                title: "Three steps, every week."
            )

            VStack(spacing: 0) {
                howItWorksRow(
                    number: "01",
                    title: "Set your number",
                    detail: "Every plan is built to fit it."
                )
                Divider().overlay(Color.reasi.border)
                howItWorksRow(
                    number: "02",
                    title: "Shop one list",
                    detail: "Real products, in aisle order."
                )
                Divider().overlay(Color.reasi.border)
                howItWorksRow(
                    number: "03",
                    title: "See where it went",
                    detail: "Each week against your target."
                )
            }
        }
    }

    private func howItWorksRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ReasiSpacing.s4) {
            Text(number)
                .font(ReasiTypography.font(size: 13, weight: .semibold, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Color.reasi.muted)
                .frame(width: 26, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
                Text(title)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ReasiSpacing.s5)
        .accessibilityElement(children: .combine)
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
                    .fixedSize(horizontal: false, vertical: true)

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
                        symbol: choice.symbol,
                        isSelected: onboarding.preferences.household == choice
                    ) {
                        onboarding.preferences.household = choice
                        ReasiHaptics.selection()
                    }
                }
            }
        }
    }

    private var budgetScreen: some View {
        let amount = onboarding.preferences.weeklyGroceryBudgetAud
            ?? WeeklyBudgetGuide.startingAmount(for: onboarding.preferences.household)

        return VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Weekly budget",
                title: "What would you like to spend each week?"
            )

            VStack(spacing: ReasiSpacing.s5) {
                HStack(spacing: ReasiSpacing.s3) {
                    budgetStepButton(symbol: "minus", label: "Ten dollars less") {
                        onboarding.setWeeklyBudget(amount - WeeklyBudgetGuide.step)
                    }
                    .disabled(amount <= WeeklyBudgetGuide.minimum)

                    VStack(spacing: ReasiSpacing.s1) {
                        Text(WeeklyBudgetGuide.wholeDollars(amount))
                            .font(ReasiTypography.font(size: 56, weight: .semibold, relativeTo: .largeTitle))
                            .monospacedDigit()
                            .foregroundStyle(Color.reasi.text)
                            .contentTransition(.numericText(value: amount))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("a week")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Weekly budget")
                    .accessibilityValue(WeeklyBudgetGuide.wholeDollars(amount))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: onboarding.setWeeklyBudget(amount + WeeklyBudgetGuide.step)
                        case .decrement: onboarding.setWeeklyBudget(amount - WeeklyBudgetGuide.step)
                        @unknown default: break
                        }
                    }

                    budgetStepButton(symbol: "plus", label: "Ten dollars more") {
                        onboarding.setWeeklyBudget(amount + WeeklyBudgetGuide.step)
                    }
                    .disabled(amount >= WeeklyBudgetGuide.maximum)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ReasiSpacing.s2) { budgetQuickPicks(current: amount) }
                    VStack(spacing: ReasiSpacing.s2) { budgetQuickPicks(current: amount) }
                }
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
            .animation(reduceMotion ? nil : ReasiMotion.tactileSpring, value: amount)

            Text("Every plan is built to fit it. You can change it any time.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { onboarding.prepareBudgetStep() }
    }

    @ViewBuilder
    private func budgetQuickPicks(current: Double) -> some View {
        ForEach(WeeklyBudgetGuide.quickPicks(for: onboarding.preferences.household), id: \.self) { pick in
            let isSelected = pick == current
            Button {
                onboarding.setWeeklyBudget(pick)
            } label: {
                Text(WeeklyBudgetGuide.wholeDollars(pick))
                    .font(ReasiTypography.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.reasi.background : Color.reasi.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSelected ? Color.reasi.text : Color.reasi.surfaceHigh, in: Capsule())
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel("\(WeeklyBudgetGuide.wholeDollars(pick)) a week")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func budgetStepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 52, height: 52)
                .background(Color.reasi.surfaceHigh, in: Circle())
        }
        .buttonStyle(ReasiPressStyle())
        .accessibilityLabel(label)
    }

    private var foodStyleScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            onboardingHeading(
                eyebrow: "Choose any that fit",
                title: "What feels good to cook?"
            )

            let chipLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: ReasiSpacing.s2))
                : AnyLayout(OnboardingChipLayout(spacing: ReasiSpacing.s2))
            chipLayout {
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
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(isSelected ? Color.reasi.background : Color.reasi.textMuted)
                        .padding(.horizontal, ReasiSpacing.s4)
                        .padding(.vertical, ReasiSpacing.s3)
                        .frame(minHeight: 48)
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

            Text("Pick a mix.")
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
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(store.retailerDisplayName)
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.muted)
                                    .fixedSize(horizontal: false, vertical: true)
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
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
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

    private var storeGuideScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            onboardingHeading(
                eyebrow: "Help build your route",
                title: "Get 3 days of Reasi Pro"
            )

            Text("Photograph your store's aisle guide to get your list in aisle order.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)

            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                HStack(spacing: ReasiSpacing.s3) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.reasi.text)
                    Text("No payment. No auto-renewal.")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                }
                Text("One reward per account. Your photo is checked before the preview starts.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
            }
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text("What to photograph")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                HStack(spacing: ReasiSpacing.s2) {
                    ForEach(["Aisle 1", "Pasta", "Sauces"], id: \.self) { label in
                        Text(label)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.text)
                            .padding(.horizontal, ReasiSpacing.s2)
                            .padding(.vertical, ReasiSpacing.s1)
                            .background(Color.reasi.surfaceHigh, in: Capsule())
                    }
                }
                Text("Look for the board near the entrance or above the aisles.")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }

            PhotosPicker(selection: $guidePhotoItem, matching: .images) {
                Label(guideSubmission == nil ? "Choose aisle guide photo" : "Choose another photo", systemImage: "photo.on.rectangle")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.reasi.surface, in: Capsule())
                    .overlay { Capsule().stroke(Color.reasi.border, lineWidth: 1) }
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(guideIsBusy)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    analytics.capture(.storeGuideCaptureStarted, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue), "source": .string("camera")])
                    showGuideCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                        .font(ReasiTypography.bodyMedium)
                        .foregroundStyle(Color.reasi.textMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(guideIsBusy)
            }

            if guideIsBusy {
                HStack(spacing: ReasiSpacing.s3) {
                    ProgressView().tint(Color.reasi.text)
                    Text("Checking the guide…")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            }

            if let guideSubmission = guideSubmission {
                VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                    Text("Guide looks clear")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text("Found \(guideSections.count) route sections. Check the order before using it.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                    ForEach(Array(guideSections.enumerated()), id: \.element.id) { index, section in
                        HStack(spacing: ReasiSpacing.s2) {
                            Text("\(index + 1)")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                                .frame(width: 20)
                            Text(section.title)
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.text)
                                .lineLimit(1)
                            Spacer()
                            Button { moveGuideSection(index, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { moveGuideSection(index, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == guideSections.count - 1)
                        }
                    }
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            }

            if let guideError {
                Text(guideError)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.warning)
            }

            Spacer(minLength: 60)
        }
    }

    private var readyScreen: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
            onboardingHeading(
                eyebrow: "Ready for your first week",
                title: "A plan shaped around you."
            )

            VStack(spacing: 0) {
                summaryRow(
                    symbol: onboarding.preferences.primaryPurpose?.symbol ?? "list.bullet",
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
                    symbol: "dollarsign.circle",
                    label: "Weekly budget",
                    value: onboarding.preferences.weeklyGroceryBudgetAud.map(WeeklyBudgetGuide.wholeDollars) ?? "No target"
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
        case .benefit, .purpose, .household, .budget, .foodStyle, .spendingTone, .store:
            "Continue"
        case .signIn:
            supabase.isSignedIn ? "Continue" : "Sign in to continue"
        case .storeGuide:
            guideSubmission == nil ? "Continue without guide" : "Use this route"
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
        case .budget:
            onboarding.preferences.weeklyGroceryBudgetAud != nil
        case .foodStyle:
            !onboarding.preferences.foodStyles.isEmpty
        case .spendingTone:
            true
        case .store:
            onboarding.preferences.selectedStoreId != nil
        case .signIn:
            supabase.isSignedIn
        case .storeGuide:
            !guideIsBusy
        case .ready:
            !onboarding.isSaving
        }
    }

    private func performBottomAction() {
        switch onboarding.currentStep {
        case .value, .benefit, .household, .budget, .foodStyle, .spendingTone, .store, .signIn:
            onboarding.advance()
        case .storeGuide:
            guard let guideSubmission else {
                analytics.capture(.storeGuideSkipped, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue), "source": .string("continue_button")])
                onboarding.advance()
                return
            }
            Task {
                do {
                    guideIsBusy = true
                    _ = try await supabase.confirmStoreGuide(submissionId: guideSubmission.submissionId, sections: guideSections)
                    analytics.capture(.storeGuideConfirmed, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue), "section_count": .int(guideSections.count)])
                    await MainActor.run {
                        guideIsBusy = false
                        onboarding.advance()
                    }
                } catch {
                    await MainActor.run {
                        guideIsBusy = false
                        guideError = supabase.userFacingMessage(for: error)
                    }
                }
            }
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
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(ReasiTypography.font(size: 34, weight: .semibold, relativeTo: .title))
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle(allowsMultiline: true))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private func authButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ReasiSpacing.s3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
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

    private func handleGuidePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ReasiServiceError.invalidResponse
            }
            await processGuideData(data)
        } catch {
            await MainActor.run {
                guideIsBusy = false
                guideError = supabase.userFacingMessage(for: error)
                analytics.capture(.storeGuideQualityFailed, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue)])
                ReasiHaptics.warning()
            }
        }
    }

    private func processGuideData(_ data: Data) async {
        await MainActor.run {
            guideIsBusy = true
            guideError = nil
            analytics.capture(.storeGuideCaptureStarted, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue)])
        }
        do {
            let uploadPath = try await supabase.uploadUserImage(data, kind: .storeGuidePhoto)
            let result = try await supabase.submitStoreGuide(storeId: onboarding.preferences.resolvedStore.id, uploadPath: uploadPath)
            await MainActor.run {
                guidePhotoData = data
                guideSubmission = result
                guideSections = result.sections
                guideIsBusy = false
                analytics.capture(.storeGuideSubmitted, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue), "section_count": .int(result.sections.count)])
                if result.reward?.granted == true {
                    analytics.capture(.storeGuideRewardGranted, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue), "duration_days": .int(3)])
                }
                ReasiHaptics.success()
            }
        } catch {
            await MainActor.run {
                guideIsBusy = false
                guideError = supabase.userFacingMessage(for: error)
                analytics.capture(.storeGuideQualityFailed, properties: ["store_id": .string(onboarding.preferences.resolvedStore.id.rawValue)])
                ReasiHaptics.warning()
            }
        }
    }

    private func moveGuideSection(_ index: Int, offset: Int) {
        let destination = index + offset
        guard guideSections.indices.contains(index), guideSections.indices.contains(destination) else { return }
        guideSections.swapAt(index, destination)
        ReasiHaptics.selection()
    }

    private func completeOnboarding() {
        Task {
            let completed = await onboarding.complete(
                supabase: supabase,
                appState: appState,
                analytics: analytics
            )
            guard completed else { return }

            coreLoop.presentPaywall(
                message: "Reasi Pro is required to create your first plan. Start your 3-day free trial to continue.",
                trigger: .onboarding
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

private struct OnboardingCameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
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

/// A sample week drawn as a till receipt: the product's promise in one glance, in the brand's monochrome.
private struct OnboardingReceiptPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let target = 150.0
    private let planned = 138.40

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack {
                Text("REASI")
                    .font(ReasiTypography.font(size: 12, weight: .bold, relativeTo: .caption))
                    .tracking(2)
                Spacer()
                Text("THIS WEEK")
                    .font(ReasiTypography.font(size: 11, weight: .semibold, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(Color.reasi.muted)
            }

            receiptRule

            VStack(spacing: ReasiSpacing.s2) {
                line("7 dinners", "$96.10")
                line("Breakfast & lunch", "$31.80")
                line("Pantry top-up", "$10.50")
            }

            receiptRule

            line("Planned basket", money(planned), emphasised: true)
            line("Weekly target", money(target))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.reasi.surfaceHigh)
                    Capsule()
                        .fill(Color.reasi.text)
                        .frame(width: proxy.size.width * (appeared ? planned / target : 0))
                }
            }
            .frame(height: 5)

            Text("\(money(target - planned)) left to spend")
                .font(ReasiTypography.font(size: 13, weight: .medium, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Color.reasi.textMuted)
        }
        .foregroundStyle(Color.reasi.text)
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.top, ReasiSpacing.s5)
        .padding(.bottom, ReasiSpacing.s6)
        .background(Color.reasi.surface, in: ReceiptShape())
        .overlay { ReceiptShape().stroke(Color.reasi.border, lineWidth: 1) }
        .rotationEffect(.degrees(-2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example week: \(money(planned)) planned against a \(money(target)) target")
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.25)) { appeared = true }
        }
    }

    private var receiptRule: some View {
        Line()
            .stroke(Color.reasi.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }

    private func line(_ label: String, _ value: String, emphasised: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(emphasised ? Color.reasi.text : Color.reasi.textMuted)
            Spacer(minLength: ReasiSpacing.s3)
            Text(value)
                .monospacedDigit()
        }
        .font(ReasiTypography.font(size: emphasised ? 16 : 14, weight: emphasised ? .semibold : .regular, relativeTo: .body))
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU")))
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }

    /// Rounded top, torn zig-zag bottom, like paper off a till.
    private struct ReceiptShape: Shape {
        func path(in rect: CGRect) -> Path {
            let radius: CGFloat = 14
            let tooth: CGFloat = 7
            let count = max(1, Int((rect.width / (tooth * 2)).rounded()))
            let step = rect.width / CGFloat(count)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - tooth))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
            for index in stride(from: count, to: 0, by: -1) {
                let x = rect.minX + CGFloat(index) * step
                path.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
                path.addLine(to: CGPoint(x: x - step, y: rect.maxY - tooth))
            }
            path.closeSubpath()
            return path
        }
    }
}
