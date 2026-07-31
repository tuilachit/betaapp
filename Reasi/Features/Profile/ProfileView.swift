import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(RevenueCatService.self) private var revenueCat

    @State private var email = ""
    @State private var password = ""
    @State private var authMessage: String?
    @State private var authIsBusy = false
    @State private var showDeleteConfirmation = false
    @State private var appleRawNonce: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                header
                authCard
                #if DEBUG
                statusCard(supabase.status)
                statusCard(analytics.status)
                statusCard(revenueCat.status)
                #endif
                accountCard
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, 120)
        }
        .background(Color.reasi.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Delete your Reasi account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                runAuthAction(mode: .deleteAccount)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, preferences, plans, shopping lists, product imports, assistant history, and uploaded photos.")
        }
        .onAppear {
            supabase.refreshAuthLabel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Circle()
                .fill(Color.reasi.surfaceHigh)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.reasi.textMuted)
                }
            Text("Profile")
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
            Text(supabase.isSignedIn ? "Signed in and ready to plan." : "Sign in to save your meal plans and shopping lists.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack(alignment: .top, spacing: ReasiSpacing.s4) {
                Image(systemName: supabase.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(supabase.isSignedIn ? Color.reasi.success : Color.reasi.text)

                VStack(alignment: .leading, spacing: 4) {
                    Text(supabase.isSignedIn ? "Account" : "Sign in")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(accountStatusText)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                }

                Spacer()
            }

            if supabase.isSignedIn {
                signedInControls
            } else {
                signedOutControls
            }

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

            VStack(spacing: ReasiSpacing.s3) {
                authField("Email", text: $email, symbol: "envelope", keyboardType: .emailAddress)
                passwordField
            }

            HStack(spacing: ReasiSpacing.s3) {
                secondaryAuthButton("Sign in", symbol: "arrow.right.circle") {
                    runAuthAction(mode: .signIn)
                }

                secondaryAuthButton("Sign up", symbol: "plus.circle") {
                    runAuthAction(mode: .signUp)
                }
            }

            HStack(spacing: ReasiSpacing.s3) {
                secondaryAuthButton("Reset password", symbol: "key") {
                    runAuthAction(mode: .resetPassword)
                }

                secondaryAuthButton("Resend email", symbol: "envelope.badge") {
                    runAuthAction(mode: .resendVerification)
                }
            }

            #if DEBUG
            if supabase.config.debugGuestAuthEnabled {
                Button {
                    runAuthAction(mode: .guest)
                } label: {
                    Label("Debug guest session", systemImage: "ladybug")
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

    private var signedInControls: some View {
        VStack(spacing: ReasiSpacing.s3) {
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

            Button {
                runAuthAction(mode: .signOut)
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.reasi.surfaceHigh, in: Capsule())
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(authIsBusy)
        }
    }

    private var accountCard: some View {
        VStack(spacing: 1) {
            profileRow("Selected store", value: appState.selectedStore.name, symbol: "shippingbox")
            privacyPolicyRow
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
                    Text(supabase.isSignedIn ? "Available" : "Sign in first")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.muted)
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.surface)
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(!supabase.isSignedIn || authIsBusy)
        }
        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    @ViewBuilder
    private var privacyPolicyRow: some View {
        if let privacyPolicyURL = supabase.config.privacyPolicyURL {
            Link(destination: privacyPolicyURL) {
                HStack(spacing: ReasiSpacing.s4) {
                    Image(systemName: "hand.raised")
                        .frame(width: 22)
                        .foregroundStyle(Color.reasi.muted)
                    Text("Privacy policy")
                        .font(ReasiTypography.bodyMedium)
                        .foregroundStyle(Color.reasi.text)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.reasi.muted)
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.surface)
            }
        } else {
            profileRow("Privacy policy", value: "URL not configured", symbol: "hand.raised")
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
        guard supabase.isSignedIn else {
            if !supabase.config.hasSupabase {
                return "Supabase is not configured. Live features are unavailable."
            }
            if supabase.config.googleClientID.isEmpty {
                return "Email is ready. Add Google client IDs to enable Google sign-in."
            }
            return "Google and email are available."
        }

        let method = supabase.currentAuthMethod?.rawValue.capitalized ?? "Supabase"
        return "\(supabase.authLabel) · \(method)"
    }

    #if DEBUG
    private func statusCard(_ status: ServiceStatus) -> some View {
        HStack(alignment: .top, spacing: ReasiSpacing.s4) {
            Image(systemName: status.state == .configured ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(status.state == .configured ? Color.reasi.success : Color.reasi.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.name)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text(status.detail)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
            }
            Spacer()
            Text(status.state.rawValue)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
        }
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }
    #endif

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

    private func profileRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
            Text(title)
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
            Spacer()
            Text(value)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface)
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
            authMessage = "Google client ID is missing from ReasiConfig.xcconfig."
            ReasiHaptics.warning()
            return
        }

        guard let rootViewController = UIApplication.shared.reasiRootViewController else {
            authMessage = "Could not find a presenting view controller for Google sign-in."
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
                authMessage = "Signed in with Google. Plan my week will use your Supabase session."
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
        authMessage = "Google Sign-In SDK is not linked yet."
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
                        ? "Signed in with Apple using Private Relay. Your real email stays hidden."
                        : "Signed in with Apple. Plan my week will use your Supabase session."
                    ReasiHaptics.success()

                case .signIn:
                    try validateEmailAndPassword()
                    analytics.capture(.authSignInStarted, properties: ["method": .string(AuthMethod.email.rawValue)])
                    try await supabase.signIn(email: trimmedEmailOrCurrentEmail, password: password)
                    captureSuccessfulAuth(method: .email, signedUp: false)
                    authMessage = supabase.emailIsVerified
                        ? "Signed in. Plan my week will use your Supabase session."
                        : "Signed in, but email is not verified yet."
                    ReasiHaptics.success()

                case .signUp:
                    try validateNewEmailAndPassword()
                    analytics.capture(.authSignInStarted, properties: ["method": .string("email_signup")])
                    try await supabase.signUp(email: trimmedEmail, password: password)
                    if supabase.isSignedIn {
                        captureSuccessfulAuth(method: .email, signedUp: true)
                        authMessage = "Account created and signed in. Plan my week will use your Supabase session."
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
                    authMessage = "Debug guest session is ready."
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
            "Google did not return an ID token."
        case .missingEmail:
            "Enter your email first."
        case .nonceGenerationFailed:
            "Could not create a secure Google sign-in nonce."
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
        .environment(RevenueCatService())
        .preferredColorScheme(.dark)
}
