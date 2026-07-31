import Foundation

struct ReasiConfig: Equatable {
    let supabaseURL: URL?
    let supabaseAnonKey: String
    let postHogKey: String
    let postHogHost: URL
    let revenueCatPublicKey: String
    let googleClientID: String
    let googleURLScheme: String
    let appleAuthEnabled: Bool
    let authRedirectURL: URL?
    let privacyPolicyURL: URL?
    let debugGuestAuthEnabled: Bool
    let debugFixtureFallbackEnabled: Bool

    var hasSupabase: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty
    }

    var hasPostHog: Bool {
        !postHogKey.isEmpty
    }

    var hasRevenueCat: Bool {
        !revenueCatPublicKey.isEmpty
    }

    static let current = ReasiConfig(
        supabaseURL: valueURL("REASI_SUPABASE_URL"),
        supabaseAnonKey: value("REASI_SUPABASE_ANON_KEY") ?? "",
        postHogKey: value("REASI_POSTHOG_KEY") ?? "",
        postHogHost: valueURL("REASI_POSTHOG_HOST") ?? URL(string: "https://us.i.posthog.com")!,
        revenueCatPublicKey: value("REASI_REVENUECAT_PUBLIC_KEY") ?? "",
        googleClientID: value("REASI_GOOGLE_CLIENT_ID") ?? "",
        googleURLScheme: value("REASI_GOOGLE_URL_SCHEME") ?? "",
        appleAuthEnabled: boolValue("REASI_ENABLE_APPLE_AUTH"),
        authRedirectURL: valueURL("REASI_AUTH_REDIRECT_URL") ?? URL(string: "ai.reasi.ios://auth/callback"),
        privacyPolicyURL: valueURL("REASI_PRIVACY_POLICY_URL"),
        debugGuestAuthEnabled: debugBoolValue("REASI_ENABLE_DEBUG_GUEST_AUTH"),
        debugFixtureFallbackEnabled: debugBoolValue("REASI_ENABLE_DEBUG_FIXTURES")
    )

    private static func value(_ key: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[key]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let rawValue = environmentValue ?? bundleValue
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func valueURL(_ key: String) -> URL? {
        guard let rawValue = value(key) else { return nil }
        return URL(string: rawValue)
    }

    private static func boolValue(_ key: String) -> Bool {
        guard let rawValue = value(key)?.lowercased() else { return false }
        return ["1", "true", "yes", "enabled"].contains(rawValue)
    }

    private static func debugBoolValue(_ key: String) -> Bool {
        #if DEBUG
        boolValue(key)
        #else
        false
        #endif
    }
}
