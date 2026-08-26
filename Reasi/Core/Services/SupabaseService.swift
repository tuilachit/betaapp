import AuthenticationServices
import Foundation
import Observation

#if canImport(Supabase)
import Supabase
#endif

@MainActor
@Observable
final class SupabaseService {
    private static let passwordRecoveryRequestKey = "ai.reasi.ios.auth.password-recovery-requested-at"
    private static let passwordRecoveryRequestLifetime: TimeInterval = 2 * 60 * 60

    let config: ReasiConfig
    let keychain: KeychainSessionStore
    private(set) var status: ServiceStatus
    private(set) var authLabel: String = "Not signed in"
    private(set) var hasActiveSession = false
    private(set) var currentUserId: String?
    private(set) var currentUserEmail: String?
    private(set) var currentAuthMethod: AuthMethod?
    private(set) var emailIsVerified = false
    private(set) var passwordRecoveryIsPending = false
    private(set) var isRestoringSession = true
    private(set) var sessionRestoreMessage: String?
    private var currentAccessToken: String?
    @ObservationIgnored private var authStateTask: Task<Void, Never>?

    #if canImport(Supabase)
    private(set) var client: SupabaseClient?
    #endif

    init(config: ReasiConfig = .current, keychain: KeychainSessionStore = KeychainSessionStore()) {
        self.config = config
        self.keychain = keychain

        if config.hasSupabase {
            status = ServiceStatus(
                name: "Supabase",
                state: .configured,
                detail: "Public URL and anon key are present."
            )
            #if canImport(Supabase)
            client = SupabaseClient(
                supabaseURL: config.supabaseURL!,
                supabaseKey: config.supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: .init(
                        storage: KeychainLocalStorage(service: "ai.reasi.ios.supabase.auth"),
                        redirectToURL: config.authRedirectURL,
                        storageKey: "ai.reasi.ios.supabase.session",
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
            refreshAuthLabel()
            observeAuthState()
            #endif
        } else {
            #if DEBUG
            let missingConfigDetail = config.debugFixtureFallbackEnabled
                ? "Missing public config; explicit debug fixtures are enabled."
                : "Missing public config. Live features are unavailable."
            #else
            let missingConfigDetail = "Missing public config. Live features are unavailable."
            #endif
            status = ServiceStatus(
                name: "Supabase",
                state: .fixtureMode,
                detail: missingConfigDetail
            )
            isRestoringSession = false
        }
    }

    var isSignedIn: Bool {
        hasActiveSession
    }

    var hasPendingEmailVerification: Bool {
        !hasActiveSession && currentAuthMethod == .email && !emailIsVerified && currentUserEmail != nil
    }

    var currentUserUsesApplePrivateRelay: Bool {
        currentUserEmail?
            .lowercased()
            .hasSuffix("@privaterelay.appleid.com") == true
    }

    func refreshAuthLabel() {
        #if canImport(Supabase)
        guard let session = client?.auth.currentSession else {
            clearSessionState()
            return
        }

        applySession(session)
        #else
        clearSessionState()
        #endif
    }

    func restoreSession() async {
        defer { isRestoringSession = false }

        #if canImport(Supabase)
        guard let client else {
            clearSessionState()
            return
        }

        guard let cachedSession = client.auth.currentSession else {
            clearSessionState()
            return
        }

        if cachedSession.isExpired {
            do {
                let refreshedSession = try await client.auth.refreshSession()
                sessionRestoreMessage = nil
                applySession(refreshedSession)
            } catch {
                if Self.isNetworkError(error) {
                    applySession(cachedSession)
                    sessionRestoreMessage = "You are offline. Reasi will reconnect your account when the network returns."
                } else {
                    try? await client.auth.signOut(scope: .local)
                    clearSessionState()
                    sessionRestoreMessage = "Your session expired. Sign in again to continue."
                }
            }
        } else {
            sessionRestoreMessage = nil
            applySession(cachedSession)
        }
        #else
        clearSessionState()
        #endif
    }

    private func clearSessionState() {
        authLabel = "Not signed in"
        hasActiveSession = false
        currentUserId = nil
        currentUserEmail = nil
        currentAuthMethod = nil
        emailIsVerified = false
        passwordRecoveryIsPending = false
        currentAccessToken = nil
        #if canImport(Supabase)
        client?.functions.setAuth(token: nil)
        #endif
    }

    private func markEmailVerificationPending(email: String, userId: String?) {
        authLabel = email
        hasActiveSession = false
        currentUserId = userId
        currentUserEmail = email
        currentAuthMethod = .email
        emailIsVerified = false
        currentAccessToken = nil
    }

    private func mappedAuthError(_ error: Error, pendingEmail: String? = nil) -> Error {
        if let authError = error as? AuthFlowError {
            return authError
        }

        if isAuthCancellation(error) {
            return AuthFlowError.cancelled
        }

        if Self.isNetworkError(error) {
            return AuthFlowError.networkUnavailable
        }

        #if canImport(Supabase)
        if let authError = error as? AuthError {
            if [
                ErrorCode.emailExists,
                .identityAlreadyExists,
                .userAlreadyExists,
            ].contains(authError.errorCode) {
                return AuthFlowError.accountExistsWithDifferentMethod
            }
            if [
                ErrorCode.emailNotConfirmed,
                .providerEmailNeedsVerification,
            ].contains(authError.errorCode) {
                if let pendingEmail {
                    markEmailVerificationPending(email: pendingEmail, userId: currentUserId)
                }
                return AuthFlowError.emailNotVerified
            }
            if authError.errorCode == .oauthProviderNotSupported ||
                authError.errorCode == .unexpectedAudience {
                return AuthFlowError.notConfigured
            }
        }
        #endif

        let message = error.localizedDescription.lowercased()
        if message.contains("email not confirmed") ||
            message.contains("email_not_confirmed") ||
            message.contains("confirm your email") ||
            message.contains("not verified") {
            if let pendingEmail {
                markEmailVerificationPending(email: pendingEmail, userId: currentUserId)
            }
            return AuthFlowError.emailNotVerified
        }
        if message.contains("already registered") ||
            message.contains("already exists") ||
            message.contains("identity is already linked") {
            return AuthFlowError.accountExistsWithDifferentMethod
        }
        if message.contains("invalid login credentials") ||
            message.contains("invalid credentials") {
            return AuthFlowError.invalidCredentials
        }
        return AuthFlowError.unexpected
    }

    func isAuthCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let authError = error as? AuthFlowError, case .cancelled = authError { return true }

        let nsError = error as NSError
        if nsError.domain == ASAuthorizationErrorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return nsError.domain == "com.google.GIDSignIn" && nsError.code == -5
    }

    func userFacingMessage(
        for error: Error,
        fallback: String = "Something went wrong. Please try again."
    ) -> String {
        if let localized = error as? AuthFlowError {
            return localized.errorDescription ?? fallback
        }
        if let localized = error as? ReasiServiceError {
            return localized.errorDescription ?? fallback
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return ReasiServiceError.timedOut.errorDescription ?? fallback
        }
        if Self.isNetworkError(error) {
            return ReasiServiceError.offline.errorDescription ?? fallback
        }
        if error is DecodingError {
            return ReasiServiceError.invalidResponse.errorDescription ?? fallback
        }

        #if canImport(Supabase)
        if let functionError = error as? FunctionsError {
            switch functionError {
            case .relayError:
                return ReasiServiceError.serviceUnavailable.errorDescription ?? fallback
            case .httpError(let code, _):
                switch code {
                case 401, 403:
                    return AuthFlowError.notSignedIn.errorDescription ?? fallback
                case 408, 504:
                    return ReasiServiceError.timedOut.errorDescription ?? fallback
                case 429:
                    return ReasiServiceError.busy.errorDescription ?? fallback
                case 500...599:
                    return ReasiServiceError.serviceUnavailable.errorDescription ?? fallback
                default:
                    return fallback
                }
            }
        }
        #endif

        return fallback
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .notConnectedToInternet,
                .networkConnectionLost,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .timedOut,
            ].contains(urlError.code)
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    #if canImport(Supabase)
    private func observeAuthState() {
        guard let client else { return }

        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled, let self else { return }

                if let session {
                    applySession(session)
                } else if event == .initialSession || event == .signedOut || event == .userDeleted {
                    clearSessionState()
                }

                if event == .passwordRecovery {
                    clearPasswordRecoveryRequest()
                    passwordRecoveryIsPending = true
                }

                if event == .initialSession {
                    isRestoringSession = false
                }
            }
        }
    }
    #endif

    #if DEBUG
    func signInAnonymously() async throws {
        #if canImport(Supabase)
        guard config.debugGuestAuthEnabled else { throw AuthFlowError.notConfigured }
        guard let client else { throw AuthFlowError.notConfigured }
        let session = try await client.auth.signInAnonymously()
        applySession(session, method: .anonymous)
        #endif
    }
    #endif

    func signIn(email: String, password: String) async throws {
        #if canImport(Supabase)
        guard let client else { throw AuthFlowError.notConfigured }
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            applySession(session, method: .email)
        } catch {
            throw mappedAuthError(error, pendingEmail: email)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func signUp(email: String, password: String) async throws {
        #if canImport(Supabase)
        guard let client else { throw AuthFlowError.notConfigured }
        do {
            clearPasswordRecoveryRequest()
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["source": .string("ios")],
                redirectTo: config.authRedirectURL
            )

            if response.session == nil, response.user.identities?.isEmpty == true {
                throw AuthFlowError.accountExistsWithDifferentMethod
            }

            if let session = response.session {
                applySession(session, method: .email)
            } else {
                markEmailVerificationPending(email: response.user.email ?? email, userId: response.user.id.uuidString)
            }
        } catch {
            throw mappedAuthError(error, pendingEmail: email)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func signInWithApple(
        idToken: String,
        nonce: String,
        profile: AppleIdentityProfile?
    ) async throws -> AppleSignInOutcome {
        #if canImport(Supabase)
        guard config.appleAuthEnabled, let client else {
            throw AuthFlowError.notConfigured
        }
        guard !nonce.isEmpty else { throw AuthFlowError.unexpected }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            let isNewUser = abs(session.user.createdAt.timeIntervalSinceNow) < 120
            applySession(session, method: .apple)

            var savedName = false
            if let profile {
                savedName = await persistAppleIdentity(profile, userId: session.user.id.uuidString)
            }

            return AppleSignInOutcome(
                isNewUser: isNewUser,
                usesPrivateRelayEmail: session.user.email?
                    .lowercased()
                    .hasSuffix("@privaterelay.appleid.com") == true,
                savedName: savedName
            )
        } catch {
            throw mappedAuthError(error)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    #if canImport(Supabase)
    private func persistAppleIdentity(_ profile: AppleIdentityProfile, userId: String) async -> Bool {
        guard let client else { return false }

        var metadata: [String: AnyJSON] = [
            "full_name": .string(profile.fullName),
        ]
        if let givenName = profile.givenName {
            metadata["given_name"] = .string(givenName)
        }
        if let familyName = profile.familyName {
            metadata["family_name"] = .string(familyName)
        }

        do {
            _ = try await client.auth.update(user: UserAttributes(data: metadata))
            try await client
                .from("profiles")
                .upsert(
                    ProfileIdentityUpsert(
                        id: userId,
                        displayName: profile.fullName,
                        updatedAt: Self.isoTimestamp(Date())
                    )
                )
                .execute()
            return true
        } catch {
            // The Supabase session is valid even if optional profile enrichment
            // cannot be saved. Apple will not necessarily return the name again.
            return false
        }
    }
    #endif

    func signInWithGoogle(idToken: String, accessToken: String?, nonce: String?) async throws {
        #if canImport(Supabase)
        guard let client else { throw AuthFlowError.notConfigured }
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken,
                    nonce: nonce
                )
            )
            applySession(session, method: .google)
        } catch {
            throw mappedAuthError(error)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func resendEmailVerification(email: String) async throws {
        #if canImport(Supabase)
        guard let client else { throw AuthFlowError.notConfigured }
        do {
            clearPasswordRecoveryRequest()
            try await client.auth.resend(email: email, type: .signup, emailRedirectTo: config.authRedirectURL)
            markEmailVerificationPending(email: email, userId: currentUserId)
        } catch {
            throw mappedAuthError(error, pendingEmail: email)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func sendPasswordReset(email: String) async throws {
        #if canImport(Supabase)
        guard let client else { throw AuthFlowError.notConfigured }
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: config.authRedirectURL)
            markPasswordRecoveryRequested()
        } catch {
            throw mappedAuthError(error)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func updatePassword(_ password: String) async throws {
        #if canImport(Supabase)
        guard let client, hasActiveSession else { throw AuthFlowError.notSignedIn }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            clearPasswordRecoveryRequest()
            passwordRecoveryIsPending = false
        } catch {
            throw mappedAuthError(error)
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func cancelPasswordRecovery() {
        clearPasswordRecoveryRequest()
        passwordRecoveryIsPending = false
    }

    func handleAuthCallback(url: URL) async -> Bool {
        #if canImport(Supabase)
        guard let client else { return false }
        do {
            let isPasswordRecovery = Self.isPasswordRecoveryCallback(url) || hasRecentPasswordRecoveryRequest()
            try await client.auth.session(from: url)
            if isPasswordRecovery {
                clearPasswordRecoveryRequest()
                passwordRecoveryIsPending = true
            }
            refreshAuthLabel()
            return hasActiveSession
        } catch {
            #if DEBUG
            print("[Reasi Supabase] Auth callback failed: \(error.localizedDescription)")
            #endif
            return false
        }
        #else
        return false
        #endif
    }

    private static func isPasswordRecoveryCallback(_ url: URL) -> Bool {
        let queryType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value
        if queryType == "recovery" { return true }

        guard let fragment = url.fragment else { return false }
        let fragmentItems = URLComponents(string: "reasi://callback?\(fragment)")?.queryItems
        return fragmentItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true
    }

    private func markPasswordRecoveryRequested() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Self.passwordRecoveryRequestKey
        )
    }

    private func hasRecentPasswordRecoveryRequest() -> Bool {
        let requestedAt = UserDefaults.standard.double(forKey: Self.passwordRecoveryRequestKey)
        guard requestedAt > 0 else { return false }

        let age = Date().timeIntervalSince1970 - requestedAt
        guard age >= 0, age <= Self.passwordRecoveryRequestLifetime else {
            clearPasswordRecoveryRequest()
            return false
        }
        return true
    }

    private func clearPasswordRecoveryRequest() {
        UserDefaults.standard.removeObject(forKey: Self.passwordRecoveryRequestKey)
    }

    func deleteAccount() async throws {
        #if canImport(Supabase)
        guard let client else { return }
        if currentAccessToken == nil, let cachedSession = client.auth.currentSession {
            applySession(cachedSession, method: currentAuthMethod)
        }

        guard let currentAccessToken else {
            throw AuthFlowError.notSignedIn
        }

        client.functions.setAuth(token: currentAccessToken)
        let response: DeleteAccountResponse = try await client.functions.invoke("delete-account")
        guard response.ok else { throw ReasiServiceError.accountDeletionFailed }
        try await signOut()
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func signOut() async throws {
        #if canImport(Supabase)
        guard let client else {
            clearSessionState()
            return
        }

        do {
            try await client.auth.signOut(scope: .global)
        } catch {
            // A user must still be able to leave the account on this device if
            // the network is unavailable or the remote session has expired.
            try await client.auth.signOut(scope: .local)
        }
        clearSessionState()
        #endif
    }

    func fetchOnboardingPreferences() async throws -> OnboardingPreferences? {
        guard config.hasSupabase else { return nil }

        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            return nil
        }

        let rows: [OnboardingPreferencesRow] = try await client
            .from("user_preferences")
            .select(
                "primary_purpose,purpose_tags,household_choice,household_size,cuisines,food_styles,dietary_constraints,preferred_store,onboarding_completed_at"
            )
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }

        let profileRows: [ProfileStoreRow] = try await client
            .from("profiles")
            .select("selected_store_id")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        var preferences = row.preferences
        if let selectedStoreId = profileRows.first?.selectedStoreId,
           let storeId = StoreID(rawValue: selectedStoreId) {
            preferences.selectedStoreId = storeId
        }
        return preferences
        #else
        return nil
        #endif
    }

    func saveOnboardingPreferences(_ preferences: OnboardingPreferences) async throws {
        guard config.hasSupabase else { throw AuthFlowError.notSignedIn }

        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let row = OnboardingPreferencesUpsert(
            userId: userId,
            purposeTags: preferences.selectedPurposes.map(\.rawValue),
            primaryPurpose: preferences.primaryPurpose?.rawValue,
            householdChoice: preferences.household?.rawValue,
            householdSize: preferences.householdSize,
            cuisines: preferences.cuisines,
            favoriteCuisines: preferences.cuisines,
            foodStyles: preferences.sortedFoodStyleValues,
            dietaryConstraints: preferences.dietaryConstraints,
            dietaryRestrictions: preferences.dietaryConstraints,
            preferredStore: preferences.resolvedStore.id.rawValue,
            onboardingCompletedAt: preferences.completedAt.map(Self.isoTimestamp),
            updatedAt: Self.isoTimestamp(Date())
        )

        try await client
            .from("user_preferences")
            .upsert(row, onConflict: "user_id")
            .execute()

        try await saveSelectedStore(preferences.resolvedStore.id)
        #else
        throw AuthFlowError.notSignedIn
        #endif
    }

    func saveSelectedStore(_ storeId: StoreID) async throws {
        guard config.hasSupabase else { return }

        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            return
        }

        try await client
            .from("profiles")
            .upsert(
                ProfileStoreUpsert(
                    id: userId,
                    selectedStoreId: storeId.rawValue,
                    updatedAt: Self.isoTimestamp(Date())
                )
            )
            .execute()
        #endif
    }

    func regroupShoppingList(shoppingListId: String, for storeId: StoreID) async throws -> WeekPlan {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            throw AuthFlowError.notSignedIn
        }

        let _: RegroupShoppingListResponse = try await client.functions.invoke(
            "regroup-shopping-list",
            options: FunctionInvokeOptions(
                body: RegroupShoppingListInput(
                    shoppingListId: shoppingListId,
                    storeId: storeId
                )
            )
        )

        guard let refreshedPlan = try await fetchLatestWeekPlan() else {
            throw ReasiServiceError.invalidResponse
        }
        return refreshedPlan
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func fetchLatestWeekPlan() async throws -> WeekPlan? {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let planRows: [PersistedMealPlanSummaryRow] = try await client
            .from("meal_plans")
            .select("id,name,store_id,week_start,planning_notes,created_at")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let planRow = planRows.first else { return nil }
        guard let storeId = planRow.storeId.flatMap(StoreID.init(rawValue:)),
              let store = FixtureStores.launchStores.first(where: { $0.id == storeId }) else {
            throw ReasiServiceError.invalidResponse
        }

        async let mealRowsRequest: [PersistedMealRow] = client
            .from("meals")
            .select(
                "id,day_label,dish,description,cuisine,cook_time_min,cost_aud,estimated_protein_g,estimated_calories,estimated_carbs_g,recipe_json,image_url,image_source_name,image_source_url,image_photographer_name,image_photographer_url,sort_order"
            )
            .eq("meal_plan_id", value: planRow.id)
            .order("sort_order")
            .execute()
            .value

        async let shoppingListRowsRequest: [PersistedShoppingListRow] = client
            .from("shopping_lists")
            .select("id,store_id,store_name,name,created_at")
            .eq("meal_plan_id", value: planRow.id)
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        let mealRows = try await mealRowsRequest
        let shoppingListRows = try await shoppingListRowsRequest
        guard let shoppingListRow = shoppingListRows.first else {
            throw ReasiServiceError.invalidResponse
        }

        let itemRows: [PersistedShoppingItemRow] = try await client
            .from("shopping_list_items")
            .select(
                "id,client_id,section_label,section_title,section_sort_key,section_type,item_name,product_name,quantity,quantity_label,checked,purchased,aisle_label,product_snapshot,sort_order,position"
            )
            .eq("shopping_list_id", value: shoppingListRow.id)
            .order("section_sort_key")
            .order("sort_order")
            .execute()
            .value

        var groupedSections: [String: RestoredSectionAccumulator] = [:]
        for row in itemRows {
            let label = row.sectionLabel ?? row.sectionTitle ?? "Location not certain"
            let key = "\(row.sectionSortKey)-\(label)"
            let item = row.shoppingListItem
            if groupedSections[key] == nil {
                groupedSections[key] = RestoredSectionAccumulator(
                    label: label,
                    sortKey: row.sectionSortKey,
                    type: row.resolvedSectionType,
                    items: []
                )
            }
            groupedSections[key]?.items.append(item)
        }

        let sections = groupedSections.values
            .sorted { lhs, rhs in
                if lhs.sortKey == rhs.sortKey { return lhs.label < rhs.label }
                return lhs.sortKey < rhs.sortKey
            }
            .map {
                ShoppingListSection(label: $0.label, sortKey: $0.sortKey, type: $0.type, items: $0.items)
            }

        let tones = ["#6f7250", "#486b58", "#805645", "#757548", "#5d5e6f", "#78566f", "#4d7370"]
        let meals = mealRows.enumerated().map { index, row in
            MealSummary(
                id: row.id,
                day: row.dayLabel,
                dish: row.dish,
                description: row.description,
                cuisine: row.cuisine,
                cookTimeMin: row.cookTimeMin,
                costAud: row.costAud,
                estimatedProteinG: Int((row.estimatedProteinG ?? 0).rounded()),
                estimatedCalories: Int((row.estimatedCalories ?? 0).rounded()),
                estimatedCarbsG: Int((row.estimatedCarbsG ?? 0).rounded()),
                tone: tones[index % tones.count],
                recipe: row.recipeJson?.normalized(fallbackCookTimeMin: row.cookTimeMin),
                imageUrl: row.imageUrl,
                imageSourceName: row.imageSourceName,
                imageSourceUrl: row.imageSourceUrl,
                imagePhotographerName: row.imagePhotographerName,
                imagePhotographerUrl: row.imagePhotographerUrl
            )
        }

        return WeekPlan(
            id: planRow.id,
            source: .supabase,
            storeId: storeId,
            storeName: shoppingListRow.storeName ?? store.name,
            weekLabel: planRow.name,
            planningNotes: planRow.planningNotes ?? "Your latest generated week.",
            meals: meals,
            shoppingList: ShoppingList(
                id: shoppingListRow.id,
                storeId: shoppingListRow.storeId.flatMap(StoreID.init(rawValue:)) ?? storeId,
                storeName: shoppingListRow.storeName ?? store.name,
                sections: sections
            )
        )
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func fetchLatestGeneratedWeekStart() async throws -> String? {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let rows: [PersistedWeekStartRow] = try await client
            .from("meal_plans")
            .select("week_start")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return rows.first?.weekStart
        #else
        return nil
        #endif
    }

    func generateWeekPlan(input: GenerateWeekPlanInput) async throws -> WeekPlan {
        guard config.hasSupabase else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return try await fixtureWeekPlan()
            }
            #endif
            throw AuthFlowError.notConfigured
        }

        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(),
              let accessToken = currentAccessToken,
              let supabaseURL = config.supabaseURL else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return try await fixtureWeekPlan()
            }
            #endif
            throw AuthFlowError.notSignedIn
        }

        let edgeRequest = EdgeGenerateWeekPlanRequest(
            storeId: input.storeId,
            weekStart: input.weekStart,
            idempotencyKey: input.idempotencyKey
        )

        do {
            var request = URLRequest(
                url: supabaseURL.appendingPathComponent("functions/v1/generate-week-plan")
            )
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(edgeRequest)

            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            guard let response = response as? HTTPURLResponse else {
                throw ReasiServiceError.invalidResponse
            }
            switch response.statusCode {
            case 200..<300:
                break
            case 401, 403:
                throw AuthFlowError.notSignedIn
            case 408, 504:
                throw ReasiServiceError.timedOut
            case 429:
                throw ReasiServiceError.busy
            case 500...599:
                throw ReasiServiceError.serviceUnavailable
            default:
                throw ReasiServiceError.invalidResponse
            }

            let generated = try JSONDecoder().decode(WeekPlan.self, from: data)
            return try await hydrateRecipes(for: generated, client: client)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ReasiServiceError.timedOut
        } catch is DecodingError {
            throw ReasiServiceError.invalidResponse
        } catch {
            throw error
        }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func uploadUserImage(_ data: Data, kind: UploadKind) async throws -> String {
        guard config.hasSupabase else { throw AuthFlowError.notSignedIn }

        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let path = "\(userId)/\(kind.rawValue)/\(UUID().uuidString).jpg"
        _ = try await client.storage
            .from("user-uploads")
            .upload(
                path,
                data: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: false
                )
            )
        return path
        #else
        throw AuthFlowError.notSignedIn
        #endif
    }

    func resolveProduct(input: ResolveProductInput) async throws -> ProductImportResult {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return ProductImportResult(batchId: nil, candidates: [Self.fixtureCandidate(named: input.query ?? input.url ?? "Imported item")])
            }
            #endif
            throw AuthFlowError.notSignedIn
        }

        return try await client.functions.invoke(
            "resolve-product",
            options: FunctionInvokeOptions(body: input)
        )
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func searchProducts(
        query: String,
        storeId: StoreID,
        limit: Int = 16
    ) async throws -> [ProductCandidate] {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return [Self.fixtureCandidate(named: query)]
            }
            #endif
            throw AuthFlowError.notSignedIn
        }

        let result: ProductImportResult = try await client.functions.invoke(
            "search-products",
            options: FunctionInvokeOptions(
                body: SearchProductsInput(query: query, storeId: storeId, limit: limit)
            )
        )
        return result.candidates
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func extractShoppingListPhoto(storeId: StoreID, uploadPath: String) async throws -> ListExtractionResult {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return Self.fixtureExtractionResult()
            }
            #endif
            throw AuthFlowError.notSignedIn
        }

        return try await client.functions.invoke(
            "extract-shopping-list-photo",
            options: FunctionInvokeOptions(body: ExtractShoppingListPhotoInput(storeId: storeId, uploadPath: uploadPath))
        )
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func compareProducts(observationIds: [String]) async throws -> ProductComparisonResult {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            throw AuthFlowError.notSignedIn
        }

        return try await client.functions.invoke(
            "compare-products",
            options: FunctionInvokeOptions(body: CompareProductsInput(productObservationIds: observationIds))
        )
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func askShoppingAssistant(
        shoppingList: ShoppingList,
        checkedItemIDs: Set<String>,
        threadId: String?,
        message: String
    ) async throws -> AssistantResponse {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil() else {
            #if DEBUG
            if config.debugFixtureFallbackEnabled {
                return AssistantResponse(
                    threadId: threadId ?? "fixture-assistant-thread",
                    message: AssistantMessage(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: "I can help once you're signed in. I won't guess prices or product facts without a reliable source.",
                        cards: [],
                        caveats: ["Explicit debug fixture response."],
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
            }
            #endif
            throw AuthFlowError.notSignedIn
        }

        let listSnapshot = ShoppingAssistantListSnapshot(
            storeId: shoppingList.storeId,
            storeName: shoppingList.storeName,
            items: shoppingList.sections.flatMap { section in
                section.items.map { item in
                    ShoppingAssistantListItemSnapshot(
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        sectionLabel: section.label,
                        aisleLabel: item.aisleLabel,
                        checked: checkedItemIDs.contains(item.id),
                        product: item.product
                    )
                }
            }
        )

        return try await client.functions.invoke(
            "shopping-assistant",
            options: FunctionInvokeOptions(
                body: ShoppingAssistantInput(
                    shoppingListId: shoppingList.id,
                    threadId: threadId,
                    message: message,
                    shoppingListSnapshot: listSnapshot
                )
            )
        )
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func addImportedCandidateToShoppingList(
        shoppingListId: String,
        candidate: ProductCandidate,
        quantity: String,
        sortOrder: Int,
        idempotencyKey: UUID
    ) async throws -> String? {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let sectionLabel = candidate.sectionLabel ?? "Location not certain"
        let sectionSortKey = candidate.sectionSortKey ?? 999
        let sectionType = candidate.sectionType ?? .unknown
        let aisleLabel = candidate.aisleLabel ?? "Location not certain"
        let productSnapshot = ProductSnapshot(candidate: candidate)
        let row = ImportedShoppingListItemInsert(
            shoppingListId: shoppingListId,
            userId: userId,
            sectionLabel: sectionLabel,
            sectionSortKey: sectionSortKey,
            sectionType: sectionType.rawValue,
            itemName: candidate.displayName,
            productName: candidate.displayName,
            quantity: Self.numericQuantity(from: quantity),
            quantityLabel: quantity,
            aisleLabel: aisleLabel,
            matchedSku: candidate.sku,
            selectedRetailer: candidate.retailer,
            selectedProductObservationId: candidate.observationId,
            selectedBarcode: candidate.barcode,
            priceCents: candidate.priceAud.map { Int(($0 * 100).rounded()) },
            priceSnapshot: CatalogPriceSnapshot(candidate: candidate),
            productSnapshot: productSnapshot,
            productSelectedAt: Self.isoTimestamp(Date()),
            sortOrder: sortOrder,
            clientId: idempotencyKey
        )

        let inserted: ImportedShoppingListItemResponse = try await client
            .from("shopping_list_items")
            .upsert(row, onConflict: "user_id,shopping_list_id,client_id")
            .select("id")
            .single()
            .execute()
            .value

        return inserted.id
        #else
        return nil
        #endif
    }

    func selectProduct(
        _ candidate: ProductCandidate,
        for item: ShoppingListItem,
        shoppingListId: String,
        sectionLabel: String,
        sectionSortKey: Int,
        sectionType: ShoppingSectionType,
        actualPriceAud: Double?
    ) async throws {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let now = Self.isoTimestamp(Date())
        let resolvedSectionLabel = candidate.sectionLabel ?? sectionLabel
        let resolvedSectionSortKey = candidate.sectionSortKey ?? sectionSortKey
        let resolvedSectionType = candidate.sectionType ?? sectionType
        let resolvedAisleLabel = candidate.aisleLabel ?? item.aisleLabel ?? "Location not certain"
        let updated: ImportedShoppingListItemResponse = try await client
            .from("shopping_list_items")
            .update(
                ShoppingListProductSelectionUpdate(
                    sectionLabel: resolvedSectionLabel,
                    sectionSortKey: resolvedSectionSortKey,
                    sectionType: resolvedSectionType.rawValue,
                    aisleLabel: resolvedAisleLabel,
                    matchedSku: candidate.sku,
                    selectedRetailer: candidate.retailer,
                    selectedProductObservationId: candidate.observationId,
                    selectedBarcode: candidate.barcode,
                    priceCents: candidate.priceAud.map { Int(($0 * 100).rounded()) },
                    priceSnapshot: CatalogPriceSnapshot(candidate: candidate, actualPriceAud: actualPriceAud),
                    actualPriceAud: actualPriceAud,
                    productSnapshot: ProductSnapshot(candidate: candidate, actualPriceAud: actualPriceAud),
                    productSelectedAt: now,
                    checked: true,
                    purchased: true,
                    checkedAt: now,
                    updatedAt: now
                )
            )
            .eq("id", value: item.id)
            .eq("shopping_list_id", value: shoppingListId)
            .eq("user_id", value: userId)
            .select("id")
            .single()
            .execute()
            .value

        guard updated.id == item.id else { throw ReasiServiceError.invalidResponse }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    func updateShoppingListItemChecked(
        itemId: String,
        shoppingListId: String,
        checked: Bool
    ) async throws {
        #if canImport(Supabase)
        guard let client = try authenticatedClientOrNil(), let userId = currentUserId else {
            throw AuthFlowError.notSignedIn
        }

        let now = Self.isoTimestamp(Date())
        let updated: ImportedShoppingListItemResponse = try await client
            .from("shopping_list_items")
            .update(
                ShoppingListItemCheckedUpdate(
                    checked: checked,
                    purchased: checked,
                    checkedAt: checked ? now : nil,
                    updatedAt: now
                )
            )
            .eq("id", value: itemId)
            .eq("shopping_list_id", value: shoppingListId)
            .eq("user_id", value: userId)
            .select("id")
            .single()
            .execute()
            .value
        guard updated.id == itemId else { throw ReasiServiceError.invalidResponse }
        #else
        throw AuthFlowError.notConfigured
        #endif
    }

    #if DEBUG
    private func fixtureWeekPlan() async throws -> WeekPlan {
        try await Task.sleep(for: .milliseconds(900))
        return FixtureWeekPlan.current
    }
    #endif

    #if canImport(Supabase)
    private func hydrateRecipes(for plan: WeekPlan, client: SupabaseClient) async throws -> WeekPlan {
        let rows: [PersistedMealRecipeRow] = try await client
            .from("meals")
            .select("id,dish,cook_time_min,recipe_json,sort_order")
            .eq("meal_plan_id", value: plan.id)
            .order("sort_order")
            .execute()
            .value

        guard !rows.isEmpty else { return plan }

        let rowsBySortOrder = Dictionary(uniqueKeysWithValues: rows.map { ($0.sortOrder, $0) })
        let hydratedMeals = plan.meals.enumerated().map { index, meal in
            guard let row = rowsBySortOrder[index], let recipe = row.recipeJson else {
                return meal
            }

            return meal.withRecipe(recipe.normalized(fallbackCookTimeMin: row.cookTimeMin ?? meal.cookTimeMin))
        }

        return plan.withMeals(hydratedMeals)
    }

    private func authenticatedClientOrNil() throws -> SupabaseClient? {
        guard let client else { return nil }
        if currentAccessToken == nil, let cachedSession = client.auth.currentSession {
            applySession(cachedSession, method: currentAuthMethod)
        }

        guard let currentAccessToken else { return nil }
        if currentAuthMethod == .email, !emailIsVerified {
            throw AuthFlowError.emailNotVerified
        }
        #if DEBUG
        if currentAuthMethod == .anonymous, !config.debugGuestAuthEnabled {
            throw AuthFlowError.notSignedIn
        }
        #else
        if currentAuthMethod == .anonymous {
            throw AuthFlowError.notSignedIn
        }
        #endif
        client.functions.setAuth(token: currentAccessToken)
        return client
    }
    #endif

    private static func numericQuantity(from value: String) -> Double {
        let token = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        return token.flatMap(Double.init) ?? 1
    }

    #if DEBUG
    private static func fixtureCandidate(named name: String) -> ProductCandidate {
        ProductCandidate(
            observationId: nil,
            name: name,
            brand: nil,
            size: nil,
            priceAud: nil,
            unitPriceAud: nil,
            unitQuantity: nil,
            unitMeasure: nil,
            comparablePrice: nil,
            imageUrl: nil,
            productUrl: nil,
            sourceName: "Fixture fallback",
            sourceUrl: nil,
            capturedAt: nil,
            freshnessLabel: "Freshness unknown",
            confidence: .low,
            confidenceReason: "No authenticated live product lookup is available.",
            uncertaintyText: "I'm not certain of the current price for this."
        )
    }

    private static func fixtureExtractionResult() -> ListExtractionResult {
        let items = [
            ListExtractionCandidate(
                extractedName: "Milk",
                quantity: "1 bottle",
                group: .needsReview,
                confidence: .low,
                confidenceReason: "Fixture fallback until live OCR is available.",
                productCandidate: fixtureCandidate(named: "Milk")
            ),
            ListExtractionCandidate(
                extractedName: "Bananas",
                quantity: "1 bunch",
                group: .needsReview,
                confidence: .low,
                confidenceReason: "Fixture fallback until live OCR is available.",
                productCandidate: fixtureCandidate(named: "Bananas")
            )
        ]
        return ListExtractionResult(batchId: nil, matched: [], needsReview: items, uncertain: [], items: items)
    }
    #endif

    private static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

#if canImport(Supabase)
private extension SupabaseService {
    func applySession(_ session: Session, method explicitMethod: AuthMethod? = nil) {
        #if DEBUG
        if session.user.isAnonymous, !config.debugGuestAuthEnabled {
            clearSessionState()
            return
        }
        #else
        if session.user.isAnonymous {
            clearSessionState()
            return
        }
        #endif

        hasActiveSession = true
        currentAccessToken = session.accessToken
        currentUserId = session.user.id.uuidString
        currentUserEmail = session.user.email
        currentAuthMethod = explicitMethod ?? AuthMethod(user: session.user)
        emailIsVerified = session.user.emailConfirmedAt != nil || session.user.confirmedAt != nil || currentAuthMethod != .email
        #if DEBUG
        if session.user.isAnonymous {
            authLabel = "Testing account"
        } else if let email = session.user.email {
            authLabel = email
        } else {
            authLabel = "Signed in"
        }
        #else
        authLabel = session.user.email ?? "Signed in"
        #endif
        client?.functions.setAuth(token: session.accessToken)
    }
}
#endif

private struct EdgeGenerateWeekPlanRequest: Encodable {
    let storeId: StoreID
    let weekStart: String?
    let idempotencyKey: String?
}

private struct OnboardingPreferencesRow: Decodable {
    let primaryPurpose: String?
    let purposeTags: [String]
    let householdChoice: String?
    let householdSize: Int
    let cuisines: [String]
    let foodStyles: [String]
    let dietaryConstraints: [String]
    let preferredStore: String?
    let onboardingCompletedAt: String?

    enum CodingKeys: String, CodingKey {
        case primaryPurpose = "primary_purpose"
        case purposeTags = "purpose_tags"
        case householdChoice = "household_choice"
        case householdSize = "household_size"
        case cuisines
        case foodStyles = "food_styles"
        case dietaryConstraints = "dietary_constraints"
        case preferredStore = "preferred_store"
        case onboardingCompletedAt = "onboarding_completed_at"
    }

    var preferences: OnboardingPreferences {
        let decodedPurposeTags = purposeTags.prefix(OnboardingPreferences.maximumPurposeSelections)
            .compactMap(OnboardingPurpose.init(rawValue:))
        let decodedPrimaryPurpose = primaryPurpose.flatMap(OnboardingPurpose.init(rawValue:))
            ?? decodedPurposeTags.first
        let orderedPurposes = OnboardingPreferences.normalizedPurposeSelection(
            [decodedPrimaryPurpose].compactMap { $0 } + decodedPurposeTags
        )
        let combinedStyles = Set(
            (foodStyles + cuisines + dietaryConstraints)
                .compactMap(FoodStyle.init(rawValue:))
        )

        return OnboardingPreferences(
            purpose: decodedPrimaryPurpose,
            purposePriorities: orderedPurposes,
            household: householdChoice.flatMap(HouseholdChoice.init(rawValue:)),
            foodStyles: combinedStyles,
            selectedStoreId: preferredStore.flatMap(StoreID.init(rawValue:)),
            completedAt: onboardingCompletedAt.flatMap(Self.date(from:))
        )
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct OnboardingPreferencesUpsert: Encodable {
    let userId: String
    let purposeTags: [String]
    let primaryPurpose: String?
    let householdChoice: String?
    let householdSize: Int
    let cuisines: [String]
    let favoriteCuisines: [String]
    let foodStyles: [String]
    let dietaryConstraints: [String]
    let dietaryRestrictions: [String]
    let preferredStore: String
    let onboardingCompletedAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case purposeTags = "purpose_tags"
        case primaryPurpose = "primary_purpose"
        case householdChoice = "household_choice"
        case householdSize = "household_size"
        case cuisines
        case favoriteCuisines = "favorite_cuisines"
        case foodStyles = "food_styles"
        case dietaryConstraints = "dietary_constraints"
        case dietaryRestrictions = "dietary_restrictions"
        case preferredStore = "preferred_store"
        case onboardingCompletedAt = "onboarding_completed_at"
        case updatedAt = "updated_at"
    }
}

private struct ProfileStoreUpsert: Encodable {
    let id: String
    let selectedStoreId: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case selectedStoreId = "selected_store_id"
        case updatedAt = "updated_at"
    }
}

private struct ProfileIdentityUpsert: Encodable {
    let id: String
    let displayName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }
}

private struct ProfileStoreRow: Decodable {
    let selectedStoreId: String

    enum CodingKeys: String, CodingKey {
        case selectedStoreId = "selected_store_id"
    }
}

enum UploadKind: String {
    case productPhoto = "product-photos"
    case shoppingListPhoto = "shopping-list-photos"
}

struct ResolveProductInput: Encodable, Hashable {
    let method: String
    let storeId: StoreID
    let query: String?
    let url: String?
    let uploadPath: String?
    var barcode: String? = nil
}

private struct SearchProductsInput: Encodable {
    let query: String
    let storeId: StoreID
    let limit: Int
}

private struct RegroupShoppingListInput: Encodable {
    let shoppingListId: String
    let storeId: StoreID
}

private struct RegroupShoppingListResponse: Decodable {
    let shoppingListId: String
    let storeId: StoreID
    let storeName: String
    let itemCount: Int
    let uncertainItemCount: Int
}

private struct ExtractShoppingListPhotoInput: Encodable {
    let storeId: StoreID
    let uploadPath: String
}

private struct CompareProductsInput: Encodable {
    let productObservationIds: [String]
}

private struct ShoppingAssistantInput: Encodable {
    let shoppingListId: String
    let threadId: String?
    let message: String
    let shoppingListSnapshot: ShoppingAssistantListSnapshot
}

private struct ShoppingAssistantListSnapshot: Encodable {
    let storeId: StoreID
    let storeName: String
    let items: [ShoppingAssistantListItemSnapshot]
}

private struct ShoppingAssistantListItemSnapshot: Encodable {
    let id: String
    let name: String
    let quantity: String
    let sectionLabel: String
    let aisleLabel: String?
    let checked: Bool
    let product: ProductSnapshot?
}

private struct ImportedShoppingListItemInsert: Encodable {
    let shoppingListId: String
    let userId: String
    let sectionLabel: String
    let sectionSortKey: Int
    let sectionType: String
    let itemName: String
    let productName: String
    let quantity: Double
    let quantityLabel: String
    let aisleLabel: String
    let matchedSku: String?
    let selectedRetailer: String?
    let selectedProductObservationId: String?
    let selectedBarcode: String?
    let priceCents: Int?
    let priceSnapshot: CatalogPriceSnapshot
    let productSnapshot: ProductSnapshot
    let productSelectedAt: String
    let sortOrder: Int
    let clientId: UUID

    enum CodingKeys: String, CodingKey {
        case shoppingListId = "shopping_list_id"
        case userId = "user_id"
        case sectionLabel = "section_label"
        case sectionSortKey = "section_sort_key"
        case sectionType = "section_type"
        case itemName = "item_name"
        case productName = "product_name"
        case quantity
        case quantityLabel = "quantity_label"
        case aisleLabel = "aisle_label"
        case matchedSku = "matched_sku"
        case selectedRetailer = "selected_retailer"
        case selectedProductObservationId = "selected_product_observation_id"
        case selectedBarcode = "selected_barcode"
        case priceCents = "price_cents"
        case priceSnapshot = "price_snapshot"
        case productSnapshot = "product_snapshot"
        case productSelectedAt = "product_selected_at"
        case sortOrder = "sort_order"
        case clientId = "client_id"
    }
}

private struct ImportedShoppingListItemResponse: Decodable {
    let id: String
}

private struct ShoppingListItemCheckedUpdate: Encodable {
    let checked: Bool
    let purchased: Bool
    let checkedAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case checked
        case purchased
        case checkedAt = "checked_at"
        case updatedAt = "updated_at"
    }
}

private struct ShoppingListProductSelectionUpdate: Encodable {
    let sectionLabel: String
    let sectionSortKey: Int
    let sectionType: String
    let aisleLabel: String
    let matchedSku: String?
    let selectedRetailer: String?
    let selectedProductObservationId: String?
    let selectedBarcode: String?
    let priceCents: Int?
    let priceSnapshot: CatalogPriceSnapshot
    let actualPriceAud: Double?
    let productSnapshot: ProductSnapshot
    let productSelectedAt: String
    let checked: Bool
    let purchased: Bool
    let checkedAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case sectionLabel = "section_label"
        case sectionSortKey = "section_sort_key"
        case sectionType = "section_type"
        case aisleLabel = "aisle_label"
        case matchedSku = "matched_sku"
        case selectedRetailer = "selected_retailer"
        case selectedProductObservationId = "selected_product_observation_id"
        case selectedBarcode = "selected_barcode"
        case priceCents = "price_cents"
        case priceSnapshot = "price_snapshot"
        case actualPriceAud = "actual_price_aud"
        case productSnapshot = "product_snapshot"
        case productSelectedAt = "product_selected_at"
        case checked
        case purchased
        case checkedAt = "checked_at"
        case updatedAt = "updated_at"
    }
}

private struct CatalogPriceSnapshot: Encodable {
    let priceAud: Double?
    let actualPriceAud: Double?
    let sourceName: String
    let sourceURL: URL?
    let capturedAt: String?
    let freshnessLabel: String

    init(candidate: ProductCandidate, actualPriceAud: Double? = nil) {
        priceAud = candidate.priceAud
        self.actualPriceAud = actualPriceAud
        sourceName = candidate.sourceName
        sourceURL = candidate.sourceUrl
        capturedAt = candidate.capturedAt
        freshnessLabel = candidate.freshnessLabel
    }
}

private struct DeleteAccountResponse: Decodable {
    let ok: Bool
}

enum AuthMethod: String, Equatable {
    case apple
    case google
    case email
    case anonymous
    case unknown

    #if canImport(Supabase)
    init(user: User) {
        if user.isAnonymous {
            self = .anonymous
            return
        }

        let providers = user.identities?.compactMap(\.provider) ?? []
        if providers.contains("apple") {
            self = .apple
        } else if providers.contains("google") {
            self = .google
        } else if user.email != nil {
            self = .email
        } else {
            self = .unknown
        }
    }
    #endif
}

struct AppleIdentityProfile: Equatable, Sendable {
    let fullName: String
    let givenName: String?
    let familyName: String?

    init?(components: PersonNameComponents?) {
        guard let components else { return nil }

        let fullName = Self.sanitized(components.formatted())
        guard let fullName else { return nil }

        self.fullName = fullName
        givenName = Self.sanitized(components.givenName)
        familyName = Self.sanitized(components.familyName)
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(120))
    }
}

struct AppleSignInOutcome: Equatable, Sendable {
    let isNewUser: Bool
    let usesPrivateRelayEmail: Bool
    let savedName: Bool
}

enum AuthFlowError: LocalizedError {
    case notSignedIn
    case notConfigured
    case emailNotVerified
    case accountExistsWithDifferentMethod
    case invalidCredentials
    case networkUnavailable
    case cancelled
    case unexpected

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in to continue."
        case .notConfigured:
            "Reasi isn't available right now. Please try again shortly."
        case .emailNotVerified:
            "Check your inbox and verify your email before continuing."
        case .accountExistsWithDifferentMethod:
            "An account already exists for this email. Use the sign-in method you originally chose."
        case .invalidCredentials:
            "That email or password does not match. Try again or reset your password."
        case .networkUnavailable:
            "You appear to be offline. Check your connection and try again."
        case .cancelled:
            "Sign-in cancelled."
        case .unexpected:
            "Sign-in could not finish. Please try again."
        }
    }
}

enum ReasiServiceError: LocalizedError {
    case offline
    case timedOut
    case busy
    case serviceUnavailable
    case invalidResponse
    case accountDeletionFailed

    var errorDescription: String? {
        switch self {
        case .offline:
            "You appear to be offline. Check your connection and try again."
        case .timedOut:
            "That took longer than expected. Your existing plan is safe; please try again."
        case .busy:
            "Reasi is busy right now. Please wait a moment and try again."
        case .serviceUnavailable:
            "Reasi could not finish that request right now. Please try again."
        case .invalidResponse:
            "We couldn't finish that request. Please try again."
        case .accountDeletionFailed:
            "Your account could not be deleted yet. Nothing was removed; please try again."
        }
    }
}

private struct PersistedMealPlanSummaryRow: Decodable {
    let id: String
    let name: String
    let storeId: String?
    let weekStart: String?
    let planningNotes: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case storeId = "store_id"
        case weekStart = "week_start"
        case planningNotes = "planning_notes"
        case createdAt = "created_at"
    }
}

private struct PersistedWeekStartRow: Decodable {
    let weekStart: String?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
    }
}

private struct PersistedMealRow: Decodable {
    let id: String
    let dayLabel: String
    let dish: String
    let description: String
    let cuisine: String
    let cookTimeMin: Int
    let costAud: Double
    let estimatedProteinG: Double?
    let estimatedCalories: Double?
    let estimatedCarbsG: Double?
    let recipeJson: RecipeInfo?
    let imageUrl: URL?
    let imageSourceName: String?
    let imageSourceUrl: URL?
    let imagePhotographerName: String?
    let imagePhotographerUrl: URL?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case dayLabel = "day_label"
        case dish
        case description
        case cuisine
        case cookTimeMin = "cook_time_min"
        case costAud = "cost_aud"
        case estimatedProteinG = "estimated_protein_g"
        case estimatedCalories = "estimated_calories"
        case estimatedCarbsG = "estimated_carbs_g"
        case recipeJson = "recipe_json"
        case imageUrl = "image_url"
        case imageSourceName = "image_source_name"
        case imageSourceUrl = "image_source_url"
        case imagePhotographerName = "image_photographer_name"
        case imagePhotographerUrl = "image_photographer_url"
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dayLabel = try container.decode(String.self, forKey: .dayLabel)
        dish = try container.decode(String.self, forKey: .dish)
        description = try container.decode(String.self, forKey: .description)
        cuisine = try container.decode(String.self, forKey: .cuisine)
        cookTimeMin = try container.decode(Int.self, forKey: .cookTimeMin)
        costAud = try container.decode(Double.self, forKey: .costAud)
        estimatedProteinG = try container.decodeIfPresent(Double.self, forKey: .estimatedProteinG)
        estimatedCalories = try container.decodeIfPresent(Double.self, forKey: .estimatedCalories)
        estimatedCarbsG = try container.decodeIfPresent(Double.self, forKey: .estimatedCarbsG)
        recipeJson = try? container.decode(RecipeInfo.self, forKey: .recipeJson)
        imageUrl = try container.decodeIfPresent(URL.self, forKey: .imageUrl)
        imageSourceName = try container.decodeIfPresent(String.self, forKey: .imageSourceName)
        imageSourceUrl = try container.decodeIfPresent(URL.self, forKey: .imageSourceUrl)
        imagePhotographerName = try container.decodeIfPresent(String.self, forKey: .imagePhotographerName)
        imagePhotographerUrl = try container.decodeIfPresent(URL.self, forKey: .imagePhotographerUrl)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }
}

private struct PersistedShoppingListRow: Decodable {
    let id: String
    let storeId: String?
    let storeName: String?
    let name: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case storeName = "store_name"
        case name
        case createdAt = "created_at"
    }
}

private struct PersistedShoppingItemRow: Decodable {
    let id: String
    let clientId: String?
    let sectionLabel: String?
    let sectionTitle: String?
    let sectionSortKey: Int
    let sectionType: String
    let itemName: String?
    let productName: String
    let quantity: Double?
    let quantityLabel: String?
    let checked: Bool
    let purchased: Bool
    let aisleLabel: String?
    let productSnapshot: ProductSnapshot?
    let sortOrder: Int
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case sectionLabel = "section_label"
        case sectionTitle = "section_title"
        case sectionSortKey = "section_sort_key"
        case sectionType = "section_type"
        case itemName = "item_name"
        case productName = "product_name"
        case quantity
        case quantityLabel = "quantity_label"
        case checked
        case purchased
        case aisleLabel = "aisle_label"
        case productSnapshot = "product_snapshot"
        case sortOrder = "sort_order"
        case position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        sectionLabel = try container.decodeIfPresent(String.self, forKey: .sectionLabel)
        sectionTitle = try container.decodeIfPresent(String.self, forKey: .sectionTitle)
        sectionSortKey = try container.decodeIfPresent(Int.self, forKey: .sectionSortKey) ?? 999
        sectionType = try container.decodeIfPresent(String.self, forKey: .sectionType) ?? ShoppingSectionType.unknown.rawValue
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName)
        productName = try container.decodeIfPresent(String.self, forKey: .productName) ?? itemName ?? "Item"
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        quantityLabel = try container.decodeIfPresent(String.self, forKey: .quantityLabel)
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        purchased = try container.decodeIfPresent(Bool.self, forKey: .purchased) ?? false
        aisleLabel = try container.decodeIfPresent(String.self, forKey: .aisleLabel)
        productSnapshot = try? container.decode(ProductSnapshot.self, forKey: .productSnapshot)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? sortOrder
    }

    var resolvedSectionType: ShoppingSectionType {
        ShoppingSectionType(rawValue: sectionType) ?? .unknown
    }

    var shoppingListItem: ShoppingListItem {
        let quantityText: String
        if let quantityLabel, !quantityLabel.isEmpty {
            quantityText = quantityLabel
        } else if let quantity {
            quantityText = quantity.rounded() == quantity
                ? String(Int(quantity))
                : String(format: "%.2f", quantity)
        } else {
            quantityText = "1"
        }

        return ShoppingListItem(
            id: id,
            name: itemName ?? productName,
            quantity: quantityText,
            checked: checked || purchased,
            aisleLabel: aisleLabel,
            sectionType: resolvedSectionType,
            product: productSnapshot,
            importedCandidate: nil,
            locationUncertaintyText: resolvedSectionType == .unknown ? "Location not certain" : nil,
            clientId: clientId
        )
    }
}

private struct RestoredSectionAccumulator {
    let label: String
    let sortKey: Int
    let type: ShoppingSectionType
    var items: [ShoppingListItem]
}

private struct PersistedMealRecipeRow: Decodable {
    let id: String?
    let dish: String?
    let cookTimeMin: Int?
    let recipeJson: RecipeInfo?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case dish
        case cookTimeMin = "cook_time_min"
        case recipeJson = "recipe_json"
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        dish = try container.decodeIfPresent(String.self, forKey: .dish)
        cookTimeMin = try container.decodeIfPresent(Int.self, forKey: .cookTimeMin)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        recipeJson = try? container.decode(RecipeInfo.self, forKey: .recipeJson)
    }
}
