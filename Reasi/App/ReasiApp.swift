import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct ReasiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var coreLoop = CoreLoopStore()
    @State private var onboarding = OnboardingStore()
    @State private var supabase = SupabaseService()
    @State private var analytics = AnalyticsService()
    @State private var revenueCat = RevenueCatService()
    @State private var network = NetworkMonitor()
    @State private var userSettings = UserSettingsStore()
    @State private var showsBrandIntro = Self.shouldShowBrandIntro
    @State private var didFinishStartup = false
    @State private var authenticationRestoreTask: Task<Void, Never>?

    private static var shouldShowBrandIntro: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-ReasiSkipBrandIntro")
        #else
        true
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ReasiRootView()

                if showsBrandIntro {
                    BrandLaunchView {
                        showsBrandIntro = false
                    }
                    .zIndex(100)
                }
            }
                .environment(appState)
                .environment(coreLoop)
                .environment(onboarding)
                .environment(supabase)
                .environment(analytics)
                .environment(revenueCat)
                .environment(network)
                .environment(userSettings)
                .preferredColorScheme(.dark)
                .tint(Color.reasi.text)
                .task {
                    await supabase.restoreSession()
                    await onboarding.bootstrap(
                        supabase: supabase,
                        appState: appState,
                        analytics: analytics
                    )
                    let expectedUserId = supabase.hasActiveSession ? supabase.currentUserId : nil
                    await restoreUserData(expectedUserId: expectedUserId)
                    analytics.capture(.appOpened)
                    didFinishStartup = true
                }
                .onChange(of: supabase.hasActiveSession) { _, hasActiveSession in
                    guard didFinishStartup else { return }
                    authenticationRestoreTask?.cancel()
                    let expectedUserId = hasActiveSession ? supabase.currentUserId : nil
                    authenticationRestoreTask = Task {
                        await onboarding.syncAfterAuthentication(
                            supabase: supabase,
                            appState: appState
                        )
                        guard !Task.isCancelled,
                              (supabase.hasActiveSession ? supabase.currentUserId : nil) == expectedUserId else { return }
                        await restoreUserData(expectedUserId: expectedUserId)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await revenueCat.refreshCustomerInfo()
                            if supabase.isSignedIn {
                                _ = try? await revenueCat.refreshServerAccess(using: supabase)
                            }
                            await coreLoop.restorePendingGeneration(
                                supabase: supabase,
                                analytics: analytics,
                                appState: appState,
                                network: network
                            )
                        }
                    } else {
                        coreLoop.pauseGenerationPolling()
                        analytics.flush()
                    }
                }
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    #endif

                    Task {
                        let didCompleteAuth = await supabase.handleAuthCallback(url: url)
                        guard didCompleteAuth, let userId = supabase.currentUserId else { return }

                        // Recovery links create a temporary authenticated session, but they are
                        // not a new sign-in and should not inflate auth analytics.
                        if supabase.passwordRecoveryIsPending {
                            return
                        }

                        let method = supabase.currentAuthMethod ?? .email
                        analytics.capture(.authSignInCompleted, properties: ["method": .string(method.rawValue)])
                        analytics.capture(.signIn, properties: [
                            "method": .string(method.rawValue),
                            "source": .string("auth_callback")
                        ])
                        analytics.identify(userId: userId, properties: [
                            "auth_method": .string(method.rawValue),
                            "email_verified": .bool(supabase.emailIsVerified)
                        ])
                    }
                }
        }
    }

    private func restoreUserData(expectedUserId: String?) async {
        guard (supabase.hasActiveSession ? supabase.currentUserId : nil) == expectedUserId else { return }
        coreLoop.activateUser(expectedUserId, selectedStore: appState.selectedStore)
        await revenueCat.syncUser(userId: expectedUserId)
        guard !Task.isCancelled,
              (supabase.hasActiveSession ? supabase.currentUserId : nil) == expectedUserId else { return }

        guard let userId = expectedUserId else {
            analytics.resetIdentity()
            return
        }

        _ = try? await revenueCat.refreshServerAccess(using: supabase)
        guard !Task.isCancelled, supabase.currentUserId == userId else { return }

        analytics.identify(userId: userId, properties: [
            "auth_method": .string(supabase.currentAuthMethod?.rawValue ?? AuthMethod.unknown.rawValue),
            "email_verified": .bool(supabase.emailIsVerified)
        ])
        await coreLoop.restoreLatestPlan(
            supabase: supabase,
            selectedStore: appState.selectedStore
        )
        guard !Task.isCancelled, supabase.currentUserId == userId else { return }
        await coreLoop.restorePendingGeneration(
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
    }
}

private struct ReasiRootView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(SupabaseService.self) private var supabase
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        VStack(spacing: 0) {
            if network.status == .offline {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack {
                if onboarding.isHydrating {
                    VStack(spacing: ReasiSpacing.s4) {
                        Text("Reasi")
                            .font(ReasiTypography.title)
                            .foregroundStyle(Color.reasi.text)
                        ProgressView()
                            .tint(Color.reasi.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.reasi.background)
                    .transition(.opacity)
                } else if onboarding.hasCompleted {
                    AppShellView()
                        .transition(.opacity)
                } else {
                    OnboardingPlaceholderView()
                        .transition(.opacity)
                }
            }
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .animation(ReasiMotion.slow, value: onboarding.isHydrating)
        .animation(ReasiMotion.slow, value: onboarding.hasCompleted)
        .animation(ReasiMotion.fast, value: network.status)
        .sheet(
            isPresented: Binding(
                get: { supabase.passwordRecoveryIsPending },
                set: { isPresented in
                    if !isPresented {
                        supabase.cancelPasswordRecovery()
                    }
                }
            )
        ) {
            PasswordRecoverySheet()
                .environment(supabase)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: ReasiSpacing.s2) {
            Image(systemName: "wifi.slash")
            Text("Offline. Live requests will wait until you reconnect.")
                .lineLimit(2)
        }
        .font(ReasiTypography.caption)
        .foregroundStyle(Color.reasi.text)
        .padding(.horizontal, ReasiSpacing.s4)
        .padding(.vertical, ReasiSpacing.s3)
        .frame(maxWidth: .infinity)
        .background(Color.reasi.surfaceHigh)
    }
}

private struct PasswordRecoverySheet: View {
    @Environment(SupabaseService.self) private var supabase

    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isBusy = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case password
        case confirmation
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                    Text("Choose a new password")
                        .font(ReasiTypography.title2)
                        .foregroundStyle(Color.reasi.text)
                    Text("Use at least 6 characters. This replaces the password for your Reasi email account.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: ReasiSpacing.s3) {
                    recoveryField(
                        "New password",
                        text: $newPassword,
                        contentType: .newPassword,
                        field: .password
                    )
                    recoveryField(
                        "Confirm password",
                        text: $confirmation,
                        contentType: .newPassword,
                        field: .confirmation
                    )
                }

                if let message {
                    Text(message)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: updatePassword) {
                    HStack(spacing: ReasiSpacing.s3) {
                        if isBusy {
                            ProgressView()
                                .tint(Color.reasi.background)
                        }
                        Text(isBusy ? "Updating..." : "Update password")
                    }
                }
                .buttonStyle(ReasiPrimaryButtonStyle())
                .disabled(isBusy)
                .opacity(isBusy ? 0.7 : 1)

                Button("Not now", action: cancelRecovery)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ReasiSpacing.s3)
                    .buttonStyle(ReasiPressStyle())
                    .disabled(isBusy)
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, ReasiSpacing.s6)
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .onAppear {
            focusedField = .password
        }
    }

    private func recoveryField(
        _ placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType,
        field: Field
    ) -> some View {
        HStack(spacing: ReasiSpacing.s3) {
            Image(systemName: "lock")
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
            SecureField(placeholder, text: text)
                .textContentType(contentType)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.text)
                .tint(Color.reasi.text)
                .focused($focusedField, equals: field)
                .submitLabel(field == .password ? .next : .done)
                .onSubmit {
                    if field == .password {
                        focusedField = .confirmation
                    } else {
                        updatePassword()
                    }
                }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private func updatePassword() {
        guard !isBusy else { return }
        guard newPassword.count >= 6 else {
            message = "Password must be at least 6 characters."
            ReasiHaptics.warning()
            return
        }
        guard newPassword == confirmation else {
            message = "The passwords do not match."
            ReasiHaptics.warning()
            return
        }

        isBusy = true
        message = nil
        ReasiHaptics.light()

        Task {
            do {
                try await supabase.updatePassword(newPassword)
                ReasiHaptics.success()
            } catch {
                message = supabase.userFacingMessage(
                    for: error,
                    fallback: "Your password could not be updated. Please request a new reset link and try again."
                )
                ReasiHaptics.warning()
            }
            isBusy = false
        }
    }

    private func cancelRecovery() {
        guard !isBusy else { return }
        isBusy = true
        message = nil

        Task {
            do {
                try await supabase.signOut()
                ReasiHaptics.selection()
            } catch {
                message = supabase.userFacingMessage(
                    for: error,
                    fallback: "Could not close password recovery. Please try again."
                )
            }
            isBusy = false
        }
    }
}
