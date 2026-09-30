import Foundation
import Observation

@MainActor
protocol SpendingService: AnyObject, Sendable {
    var authenticatedUserId: String? { get }
    var authIdentityRevision: Int { get }
    var isSignedIn: Bool { get }
    func fetchSpendingDashboard(period: SpendingPeriod, anchorDate: String?) async throws -> SpendingDashboard
    func fetchSpendingTripDetail(tripId: String) async throws -> SpendingTripDetail
    func correctShoppingTotal(tripId: String, totalAud: Double) async throws -> SpendingTotalCorrection
    func retrySpendingInsight(tripId: String) async throws
    func userFacingMessage(for error: Error, fallback: String) -> String
}

extension SupabaseService: SpendingService {}

enum SpendingInsightLoadState {
    static func canRetry(_ status: String?) -> Bool { status == "failed" || status == "stale" }
    static func isPending(_ status: String?) -> Bool {
        status == "pending" || status == "in_progress" || status == "missing"
    }
    static func isTerminal(_ status: String?) -> Bool { status == "completed" || canRetry(status) }
}

@MainActor
@Observable
final class SpendingStore {
    var period: SpendingPeriod = .week
    private(set) var dashboard: SpendingDashboard?
    private(set) var selectedTrip: SpendingTripDetail?
    private(set) var isLoadingDashboard = false
    private(set) var isLoadingTrip = false
    private(set) var isRetryingInsights = false
    private(set) var dashboardMessage: String?
    private(set) var tripMessage: String?

    @ObservationIgnored private let cache: SpendingLocalCache
    @ObservationIgnored private var activeUserId: String?
    @ObservationIgnored private var identityRevision = 0
    @ObservationIgnored private var dashboardRequest: UUID?
    @ObservationIgnored private var tripRequest: UUID?

    init(cache: SpendingLocalCache = SpendingLocalCache()) {
        self.cache = cache
    }

    func activate(userId: String?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            activeUserId = "spend-ui-test-user"
            period = .week
            dashboard = .uiTestFixture(for: .week)
            selectedTrip = .uiTestFixture
            dashboardMessage = nil
            tripMessage = nil
            return
        }
        #endif

        guard activeUserId != userId else { return }
        activeUserId = userId
        identityRevision += 1
        dashboardRequest = nil
        tripRequest = nil
        isLoadingDashboard = false
        isLoadingTrip = false
        isRetryingInsights = false
        period = .week
        selectedTrip = nil
        tripMessage = nil
        dashboardMessage = nil
        dashboard = userId.flatMap { cache.loadDashboard(userId: $0, period: .week) }
    }

    func selectPeriod(
        _ newPeriod: SpendingPeriod,
        supabase: any SpendingService,
        analytics: AnalyticsService
    ) async {
        guard period != newPeriod else { return }
        period = newPeriod
        if let userId = activeUserId,
           let cached = cache.loadDashboard(userId: userId, period: newPeriod) {
            dashboard = cached
        } else {
            dashboard = nil
        }
        analytics.capture(.spendingPeriodChanged, properties: [
            "period": .string(newPeriod.rawValue)
        ])
        await refresh(supabase: supabase)
    }

    func refresh(supabase: any SpendingService) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            dashboard = .uiTestFixture(for: period)
            dashboardMessage = nil
            return
        }
        #endif

        guard let userId = activeUserId, supabase.authenticatedUserId == userId else {
            dashboard = nil
            dashboardMessage = "Sign in to keep your shopping history and spending insights together."
            return
        }

        let identity = identityRevision
        let authIdentity = supabase.authIdentityRevision
        let requestedPeriod = period
        let request = UUID()
        dashboardRequest = request
        func isCurrent() -> Bool {
            !Task.isCancelled && activeUserId == userId && identityRevision == identity
                && supabase.authenticatedUserId == userId && supabase.authIdentityRevision == authIdentity
                && dashboardRequest == request && period == requestedPeriod
        }
        isLoadingDashboard = dashboard == nil
        dashboardMessage = nil
        defer { if dashboardRequest == request { isLoadingDashboard = false } }

        do {
            let loaded = try await supabase.fetchSpendingDashboard(period: requestedPeriod, anchorDate: nil)
            guard isCurrent(), loaded.period == requestedPeriod else { return }
            dashboard = loaded
            cache.saveDashboard(loaded, userId: userId)
        } catch {
            guard isCurrent() else { return }
            if dashboard == nil {
                dashboard = cache.loadDashboard(userId: userId, period: period)
            }
            dashboardMessage = dashboard == nil
                ? supabase.userFacingMessage(
                    for: error,
                    fallback: "Your spending could not load yet. Check your connection and try again."
                )
                : "Showing your last saved spending view."
        }
    }

    func loadTrip(
        id: String,
        supabase: any SpendingService,
        pollForInsights: Bool = true
    ) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            selectedTrip = .uiTestFixture
            tripMessage = nil
            return
        }
        #endif

        guard let userId = activeUserId, supabase.authenticatedUserId == userId else {
            selectedTrip = nil
            tripMessage = "Sign in to view this shop."
            return
        }

        let identity = identityRevision
        let authIdentity = supabase.authIdentityRevision
        let request = UUID()
        tripRequest = request
        func isCurrent() -> Bool {
            !Task.isCancelled && activeUserId == userId && identityRevision == identity
                && supabase.authenticatedUserId == userId && supabase.authIdentityRevision == authIdentity
                && tripRequest == request
        }
        if selectedTrip?.trip.id != id {
            selectedTrip = cache.loadTrip(userId: userId, tripId: id)
        }
        isLoadingTrip = selectedTrip == nil
        tripMessage = nil
        defer { if tripRequest == request { isLoadingTrip = false } }

        let maximumAttempts = pollForInsights ? 4 : 1
        for attempt in 0..<maximumAttempts {
            guard isCurrent() else { return }
            do {
                let detail = try await supabase.fetchSpendingTripDetail(tripId: id)
                guard isCurrent(), detail.trip.id == id else { return }
                selectedTrip = detail
                cache.saveTrip(detail, userId: userId)

                let insightIsReady = SpendingInsightLoadState.isTerminal(detail.insightStatus)
                if insightIsReady || attempt == maximumAttempts - 1 { return }
                try await Task.sleep(for: .seconds(2))
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent() else { return }
                if selectedTrip == nil {
                    selectedTrip = cache.loadTrip(userId: userId, tripId: id)
                }
                tripMessage = selectedTrip == nil
                    ? supabase.userFacingMessage(
                        for: error,
                        fallback: "This shop could not load yet. Check your connection and try again."
                    )
                    : "Showing the last saved recap."
                return
            }
        }
    }

    func refreshAfterCompletedTrip(
        tripId: String,
        supabase: any SpendingService
    ) async {
        async let dashboardRefresh: Void = refresh(supabase: supabase)
        async let tripRefresh: Void = loadTrip(id: tripId, supabase: supabase)
        _ = await (dashboardRefresh, tripRefresh)
    }

    func correctTotal(
        tripId: String,
        totalAud: Double,
        supabase: any SpendingService,
        analytics: AnalyticsService
    ) async -> Bool {
        guard let userId = activeUserId, supabase.authenticatedUserId == userId else { return false }
        let identity = identityRevision
        let authIdentity = supabase.authIdentityRevision
        func isCurrent() -> Bool {
            !Task.isCancelled && activeUserId == userId && identityRevision == identity
                && supabase.authenticatedUserId == userId && supabase.authIdentityRevision == authIdentity
        }
        tripMessage = nil
        do {
            _ = try await supabase.correctShoppingTotal(tripId: tripId, totalAud: totalAud)
            guard isCurrent() else { return false }
            analytics.capture(.spendingTotalCorrected, properties: [
                "trip_id": .string(tripId)
            ])
            await refreshAfterCompletedTrip(tripId: tripId, supabase: supabase)
            guard isCurrent() else { return false }
            ReasiHaptics.success()
            return true
        } catch {
            guard isCurrent() else { return false }
            tripMessage = supabase.userFacingMessage(
                for: error,
                fallback: "The checkout total could not be updated. Please try again."
            )
            ReasiHaptics.warning()
            return false
        }
    }

    func retryInsights(
        tripId: String,
        supabase: any SpendingService
    ) async {
        guard !isRetryingInsights, let userId = activeUserId,
              supabase.authenticatedUserId == userId else { return }
        let identity = identityRevision
        let authIdentity = supabase.authIdentityRevision
        func isCurrent() -> Bool {
            !Task.isCancelled && activeUserId == userId && identityRevision == identity
                && supabase.authenticatedUserId == userId && supabase.authIdentityRevision == authIdentity
        }
        isRetryingInsights = true
        dashboardMessage = nil
        tripMessage = nil
        defer { if identityRevision == identity { isRetryingInsights = false } }

        do {
            try await supabase.retrySpendingInsight(tripId: tripId)
            try await Task.sleep(for: .milliseconds(500))
            guard isCurrent() else { return }
            await refreshAfterCompletedTrip(tripId: tripId, supabase: supabase)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent() else { return }
            let message = supabase.userFacingMessage(
                for: error,
                fallback: "Your insights could not refresh yet. Please try again."
            )
            dashboardMessage = message
            tripMessage = message
            ReasiHaptics.warning()
        }
    }
}

final class SpendingLocalCache {
    private let directoryURL: URL?
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.directoryURL = directoryURL ?? base?.appendingPathComponent("ReasiSpending", isDirectory: true)
        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } else if let directoryURL = self.directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func loadDashboard(userId: String, period: SpendingPeriod) -> SpendingDashboard? {
        load(SpendingDashboard.self, from: fileURL(userId: userId, name: "dashboard-\(period.rawValue)"))
    }

    func saveDashboard(_ dashboard: SpendingDashboard, userId: String) {
        save(dashboard, to: fileURL(userId: userId, name: "dashboard-\(dashboard.period.rawValue)"))
    }

    func loadTrip(userId: String, tripId: String) -> SpendingTripDetail? {
        load(SpendingTripDetail.self, from: fileURL(userId: userId, name: "trip-\(tripId)"))
    }

    func saveTrip(_ detail: SpendingTripDetail, userId: String) {
        save(detail, to: fileURL(userId: userId, name: "trip-\(detail.trip.id)"))
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL?) {
        guard let url, let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func fileURL(userId: String, name: String) -> URL? {
        let safeUserId = userId.replacingOccurrences(of: "/", with: "_")
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        let userDirectory = directoryURL?.appendingPathComponent(safeUserId, isDirectory: true)
        if let userDirectory {
            try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        }
        return userDirectory?.appendingPathComponent("\(safeName).json")
    }
}
