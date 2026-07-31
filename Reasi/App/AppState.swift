import Foundation
import Network
import Observation

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    var selectedStore: StoreSummary
    var activePlan: WeekPlan = FixtureWeekPlan.current

    let homeRouter = RouterPath()
    let plansRouter = RouterPath()
    let listRouter = RouterPath()
    let profileRouter = RouterPath()

    @ObservationIgnored private let defaults: UserDefaults
    private let selectedStoreKey = "reasi.selectedStoreId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedId = defaults.string(forKey: selectedStoreKey)
        selectedStore = FixtureStores.launchStores.first { $0.id.rawValue == storedId } ?? FixtureStores.topRyde
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
        case .profile:
            profileRouter
        }
    }

    func showPlan() {
        selectedTab = .plans
    }

    func showShoppingList() {
        selectedTab = .list
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
