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
    /// True when Spend can't load because nobody is signed in, as opposed to a connection problem.
    private(set) var needsSignIn = false
    private(set) var tripMessage: String?
    /// Items bought in more than one recent finished shop. Empty until there are two shops.
    private(set) var usuals: [UsualItem] = []

    @ObservationIgnored private let cache = SpendingLocalCache()
    @ObservationIgnored private var activeUserId: String?
    @ObservationIgnored private var usualsUserId: String?
    @ObservationIgnored private var isLoadingUsuals = false

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
        usuals = []
        usualsUserId = nil
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
            dashboard = .uiTestFixture(for: period)
            dashboardMessage = nil
            return
        }
        #endif

        guard let userId = activeUserId, supabase.isSignedIn else {
            dashboard = nil
            needsSignIn = true
            dashboardMessage = "Sign in to keep your shopping history and spending insights together."
            return
        }
        needsSignIn = false

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
        await refreshUsuals(supabase: supabase, force: true)
    }

    /// Works out the household's usual items from their last few finished shops.
    /// Shop details are kept on the device, so only shops not seen before are fetched.
    func refreshUsuals(supabase: SupabaseService, force: Bool = false) async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ReasiShowShoppingFixture") || arguments.contains("-ReasiShowSpendFixture") {
            usuals = ShoppingHabits.usuals(from: SpendingTripDetail.usualsFixture)
            return
        }
        #endif

        guard let userId = activeUserId, supabase.isSignedIn else {
            usuals = []
            return
        }
        guard force || usualsUserId != userId, !isLoadingUsuals else { return }
        isLoadingUsuals = true
        defer { isLoadingUsuals = false }

        do {
            var trips: [String: SpendingRecentTrip] = [:]
            for anchor in Self.usualsAnchorDates() {
                let dashboard = try await supabase.fetchSpendingDashboard(period: .month, anchorDate: anchor)
                guard activeUserId == userId else { return }
                for trip in dashboard.recentTrips { trips[trip.tripId] = trip }
                if trips.count >= ShoppingHabits.shopsToConsider { break }
            }

            let recent = trips.values
                .sorted { (PriceFreshness.parse($0.completedAt) ?? .distantPast) > (PriceFreshness.parse($1.completedAt) ?? .distantPast) }
                .prefix(ShoppingHabits.shopsToConsider)

            var details: [SpendingTripDetail] = []
            for trip in recent {
                if let cached = cache.loadTrip(userId: userId, tripId: trip.tripId) {
                    details.append(cached)
                    continue
                }
                // One shop failing to load shouldn't hide the rest.
                guard let detail = try? await supabase.fetchSpendingTripDetail(tripId: trip.tripId) else { continue }
                guard activeUserId == userId else { return }
                cache.saveTrip(detail, userId: userId)
                details.append(detail)
            }

            guard activeUserId == userId else { return }
            usuals = ShoppingHabits.usuals(from: details)
            usualsUserId = userId
        } catch {
            // Usuals are a shortcut, not a requirement; keep whatever was shown before.
        }
    }

    /// This month and last month, as the month anchors the spending dashboard expects.
    static func usualsAnchorDates(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-01"
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        return [formatter.string(from: now), formatter.string(from: lastMonth)]
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
