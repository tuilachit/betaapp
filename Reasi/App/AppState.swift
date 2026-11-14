import Foundation
import Network
import Observation

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    var selectedStore: StoreSummary
    var activePlan: WeekPlan = FixtureWeekPlan.current
    var planBuilderRequest: PlanBuilderRequest?
    let planBuilder = PlanBuilderStore()
    private(set) var shoppingListAddRequest = 0

    let homeRouter = RouterPath()
    let plansRouter = RouterPath()
    let listRouter = RouterPath()
    let spendRouter = RouterPath()

    @ObservationIgnored private let defaults: UserDefaults
    private let selectedStoreKey = "reasi.selectedStoreId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedId = defaults.string(forKey: selectedStoreKey)
        selectedStore = FixtureStores.launchStores.first { $0.id.rawValue == storedId } ?? FixtureStores.topRyde
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ReasiOpenShoppingList") {
            selectedTab = .list
        } else if ProcessInfo.processInfo.arguments.contains("-ReasiShowShoppingFixture") {
            selectedStore = FixtureStores.topRyde
            selectedTab = .list
        } else if ProcessInfo.processInfo.arguments.contains("-ReasiShowSpendFixture") {
            selectedTab = .spend
        }
        #endif
    }

    func selectStore(_ store: StoreSummary) {
        selectedStore = store
        defaults.set(store.id.rawValue, forKey: selectedStoreKey)
    }

    func router(for tab: AppTab) -> RouterPath {
        switch tab {
        case .home:
            homeRouter
        case .plans:
            plansRouter
        case .list:
            listRouter
        case .spend:
            spendRouter
        }
    }

    func showPlan() {
        selectedTab = .plans
    }

    func showShoppingList() {
        selectedTab = .list
    }

    func showSpend() {
        selectedTab = .spend
    }

    func openProfile() {
        router(for: selectedTab).navigate(to: .profile)
    }

    func openSpendingTrip(_ tripId: String) {
        selectedTab = .spend
        spendRouter.path = [.spendingTrip(id: tripId)]
    }

    func requestShoppingListAdd() {
        selectedTab = .list
        shoppingListAddRequest &+= 1
    }

    func openPlanBuilder(entryMethod: EntryMethod) {
        ReasiHaptics.light()
        planBuilderRequest = PlanBuilderRequest(entryMethod: entryMethod)
    }
}

struct PlanBuilderRequest: Identifiable, Hashable {
    let id = UUID()
    let entryMethod: EntryMethod
}

@MainActor
@Observable
final class PlanBuilderStore {
    private(set) var draft: PlanBrief?
    private(set) var activeUserId: String?

    @ObservationIgnored private let cache = PlanBuilderDraftCache()

    func activate(userId: String?) {
        activeUserId = userId
        draft = userId.flatMap(cache.load)
    }

    /// Starts a new draft unless one is in progress. A new draft takes the household size and,
    /// for a week plan, the weekly budget saved in Profile, so the user never re-enters them.
    func begin(entryMethod: EntryMethod, householdSize: Int? = nil, weeklyBudgetAud: Double? = nil) {
        guard draft == nil else { return }
        let kind: PlanKind = entryMethod == .describe ? .occasion : .week
        var brief = PlanBrief(kind: kind, entryMethod: entryMethod)
        if let householdSize, householdSize > 0 {
            brief.serves = householdSize
        }
        if kind == .week, let weeklyBudgetAud, weeklyBudgetAud.isFinite, weeklyBudgetAud > 0 {
            brief.budgetTargetAud = weeklyBudgetAud
        }
        update(brief)
    }

    func update(_ brief: PlanBrief) {
        draft = brief
        guard let activeUserId else { return }
        cache.save(brief, userId: activeUserId)
    }

    func discard() {
        draft = nil
        guard let activeUserId else { return }
        cache.remove(userId: activeUserId)
    }
}

private final class PlanBuilderDraftCache {
    private let directoryURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directoryURL = base?.appendingPathComponent("ReasiPlanBuilder", isDirectory: true)
        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(userId: String) -> PlanBrief? {
        guard let url = fileURL(userId), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PlanBrief.self, from: data)
    }

    func save(_ brief: PlanBrief, userId: String) {
        guard let url = fileURL(userId), let data = try? encoder.encode(brief) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(userId: String) {
        guard let url = fileURL(userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL(_ userId: String) -> URL? {
        let safeUserId = userId.replacingOccurrences(of: "/", with: "_")
        return directoryURL?.appendingPathComponent("draft-\(safeUserId).json")
    }
}

enum NetworkStatus: Equatable {
    case checking
    case online
    case offline
}

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var status: NetworkStatus = .checking

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "ai.reasi.ios.network-monitor")

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reasi-force-offline") {
            status = .offline
            return
        }
        #endif

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.status = path.status == .satisfied ? .online : .offline
            }
        }
        monitor.start(queue: queue)
    }

    var isConnected: Bool {
        status != .offline
    }
}
