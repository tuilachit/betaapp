import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        TabView(selection: Binding<ShellTab>(
            get: { .screen(appState.selectedTab) },
            set: { selection in
                switch selection {
                case .screen(let tab):
                    appState.selectedTab = tab
                case .add:
                    // The + sits in the tab bar but isn't a screen: it acts, and the tab stays put.
                    performPrimaryAction()
                }
            }
        )) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbolName, value: ShellTab.screen(tab)) {
                    tabStack(for: tab)
                }
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
            // The search role gives the system's separate round button at the end of the bar.
            Tab(primaryActionLabel, systemImage: "plus", value: ShellTab.add, role: .search) {
                Color.reasi.background.ignoresSafeArea()
            }
            .accessibilityIdentifier("tab-add")
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.reasi.text)
        .background(Color.reasi.background.ignoresSafeArea())
        .fullScreenCover(item: Binding(
            get: { appState.planBuilderRequest },
            set: { appState.planBuilderRequest = $0 }
        )) { request in
            PlanBuilderView(entryMethod: request.entryMethod)
        }
        .sheet(
            item: Binding(
                get: { coreLoop.paywallRequest },
                set: { request in
                    if request == nil {
                        coreLoop.dismissPaywall()
                    }
                }
            )
        ) { request in
            ReasiProPaywallView(reason: request.message, trigger: request.trigger) {
                coreLoop.dismissPaywall()
                startGeneration()
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-reasi-show-paywall") {
                coreLoop.presentDebugPaywall()
            }
        }
        #endif
    }

    private enum ShellTab: Hashable {
        case screen(AppTab)
        case add
    }

    private var addsToList: Bool {
        appState.selectedTab == .list && coreLoop.hasPlan && !coreLoop.isShoppingCompleted
    }

    private var primaryActionLabel: String {
        addsToList ? "Add shopping item" : "Create a plan"
    }

    private func performPrimaryAction() {
        ReasiHaptics.light()
        if addsToList {
            appState.requestShoppingListAdd()
        } else {
            appState.openPlanBuilder(entryMethod: .build)
        }
    }

    @ViewBuilder
    private func tabStack(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: Binding(
                get: { appState.homeRouter.path },
                set: { appState.homeRouter.path = $0 }
            )) {
                HomeView()
                    .withReasiNavigationDestinations()
            }
        case .plans:
            NavigationStack(path: Binding(
                get: { appState.plansRouter.path },
                set: { appState.plansRouter.path = $0 }
            )) {
                WeekPlanPlaceholderView()
                    .withReasiNavigationDestinations()
            }
        case .list:
            NavigationStack(path: Binding(
                get: { appState.listRouter.path },
                set: { appState.listRouter.path = $0 }
            )) {
                ShoppingListPlaceholderView()
                    .withReasiNavigationDestinations()
            }
        case .spend:
            NavigationStack(path: Binding(
                get: { appState.spendRouter.path },
                set: { appState.spendRouter.path = $0 }
            )) {
                SpendView()
                    .withReasiNavigationDestinations()
            }
        }
    }

    private func startGeneration() {
        coreLoop.startWeekPlanGeneration(
            store: appState.selectedStore,
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
    }
}

private extension View {
    func withReasiNavigationDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .meal(let id):
                Text("Meal \(id)")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.reasi.background)
            case .section(let label):
                Text(label)
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.reasi.background)
            case .profile:
                ProfileView()
            case .spendingTrip(let id):
                SpendingTripDetailView(tripId: id)
            case .spendingInsight(let card):
                SpendingInsightDetailView(card: card)
            }
        }
    }
}

#Preview {
    AppShellView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(RevenueCatService())
        .environment(NetworkMonitor())
        .environment(OnboardingStore())
        .environment(UserSettingsStore())
        .environment(SpendingStore())
        .preferredColorScheme(.dark)
}
