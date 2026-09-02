import Foundation
import Observation

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

    @ObservationIgnored private let cache = SpendingLocalCache()
    @ObservationIgnored private var activeUserId: String?

    func activate(userId: String?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            activeUserId = "spend-ui-test-user"
            period = .week
            dashboard = .uiTestFixture
            selectedTrip = .uiTestFixture
            dashboardMessage = nil
            tripMessage = nil
            return
        }
        #endif

        guard activeUserId != userId else { return }
        activeUserId = userId
        period = .week
        selectedTrip = nil
        tripMessage = nil
        dashboardMessage = nil
        dashboard = userId.flatMap { cache.loadDashboard(userId: $0, period: .week) }
    }

    func selectPeriod(
        _ newPeriod: SpendingPeriod,
        supabase: SupabaseService,
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

    func refresh(supabase: SupabaseService) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            dashboard = .uiTestFixture
            dashboardMessage = nil
            return
        }
        #endif

        guard let userId = activeUserId, supabase.isSignedIn else {
            dashboard = nil
            dashboardMessage = "Sign in to keep your shopping history and spending insights together."
            return
        }

        isLoadingDashboard = dashboard == nil
        dashboardMessage = nil
        defer { isLoadingDashboard = false }

        do {
            let loaded = try await supabase.fetchSpendingDashboard(period: period)
            guard activeUserId == userId, loaded.period == period else { return }
            dashboard = loaded
            cache.saveDashboard(loaded, userId: userId)
        } catch {
            guard activeUserId == userId else { return }
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
        supabase: SupabaseService,
        pollForInsights: Bool = true
    ) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            selectedTrip = .uiTestFixture
            tripMessage = nil
            return
        }
        #endif

        guard let userId = activeUserId, supabase.isSignedIn else {
            selectedTrip = nil
            tripMessage = "Sign in to view this shop."
            return
        }

        if selectedTrip?.trip.id != id {
            selectedTrip = cache.loadTrip(userId: userId, tripId: id)
        }
        isLoadingTrip = selectedTrip == nil
        tripMessage = nil
        defer { isLoadingTrip = false }

        let maximumAttempts = pollForInsights ? 4 : 1
        for attempt in 0..<maximumAttempts {
            guard !Task.isCancelled, activeUserId == userId else { return }
            do {
                let detail = try await supabase.fetchSpendingTripDetail(tripId: id)
                guard activeUserId == userId, detail.trip.id == id else { return }
                selectedTrip = detail
                cache.saveTrip(detail, userId: userId)

                let insightIsReady = detail.insightStatus == "completed" || detail.insightStatus == "failed"
                if insightIsReady || attempt == maximumAttempts - 1 { return }
                try await Task.sleep(for: .seconds(2))
            } catch is CancellationError {
                return
            } catch {
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
        supabase: SupabaseService
    ) async {
        async let dashboardRefresh: Void = refresh(supabase: supabase)
        async let tripRefresh: Void = loadTrip(id: tripId, supabase: supabase)
        _ = await (dashboardRefresh, tripRefresh)
    }

    func correctTotal(
        tripId: String,
        totalAud: Double,
        supabase: SupabaseService,
        analytics: AnalyticsService
    ) async -> Bool {
        tripMessage = nil
        do {
            _ = try await supabase.correctShoppingTotal(tripId: tripId, totalAud: totalAud)
            analytics.capture(.spendingTotalCorrected, properties: [
                "trip_id": .string(tripId)
            ])
            await refreshAfterCompletedTrip(tripId: tripId, supabase: supabase)
            ReasiHaptics.success()
            return true
        } catch {
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
        supabase: SupabaseService
    ) async {
        guard !isRetryingInsights else { return }
        isRetryingInsights = true
        dashboardMessage = nil
        tripMessage = nil
        defer { isRetryingInsights = false }

        do {
            try await supabase.retrySpendingInsight(tripId: tripId)
            try await Task.sleep(for: .milliseconds(500))
            await refreshAfterCompletedTrip(tripId: tripId, supabase: supabase)
        } catch is CancellationError {
            return
        } catch {
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
