import Foundation
import Observation

#if canImport(RevenueCat)
import RevenueCat
#endif

@MainActor
@Observable
final class RevenueCatService {
    let config: ReasiConfig
    private(set) var status: ServiceStatus

    init(config: ReasiConfig = .current) {
        self.config = config

        status = ServiceStatus(
            name: "RevenueCat",
            state: config.hasRevenueCat ? .dormant : .fixtureMode,
            detail: config.hasRevenueCat ? "Public SDK key present; paywall disabled." : "No public SDK key present."
        )
    }

    var isReasiProActive: Bool {
        false
    }

    func refreshEntitlements() async {
        guard config.hasRevenueCat else { return }

        // Phase 5 wires entitlement refresh and paywall surfaces.
        #if canImport(RevenueCat)
        _ = config.revenueCatPublicKey
        #endif
    }
}
