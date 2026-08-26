import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        ZStack(alignment: .bottom) {
            tabStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(
                selectedTab: Binding(
                    get: { appState.selectedTab },
                    set: { appState.selectedTab = $0 }
                ),
                primaryActionSymbol: primaryActionSymbol,
                primaryActionLabel: primaryActionLabel,
                primaryAction: performPrimaryAction
            )
        }
        .background(Color.reasi.background.ignoresSafeArea())
        .onChange(of: appState.selectedStore.id, initial: true) { _, _ in
            coreLoop.requestStoreSwitch(
                to: appState.selectedStore,
                supabase: supabase,
                analytics: analytics
            )
        }
        .onChange(of: coreLoop.plan.id, initial: true) { _, _ in
            coreLoop.requestStoreSwitch(
                to: appState.selectedStore,
                supabase: supabase,
                analytics: analytics
            )
        }
    }

    @ViewBuilder
    private var tabStack: some View {
        switch appState.selectedTab {
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
        case .profile:
            NavigationStack(path: Binding(
                get: { appState.profileRouter.path },
                set: { appState.profileRouter.path = $0 }
            )) {
                ProfileView()
                    .withReasiNavigationDestinations()
            }
        }
    }

    private var primaryActionSymbol: String {
        appState.selectedTab == .list && coreLoop.hasPlan ? "cart.badge.plus" : "plus"
    }

    private var primaryActionLabel: String {
        appState.selectedTab == .list && coreLoop.hasPlan
            ? "Add shopping item"
            : "Create week plan"
    }

    private func performPrimaryAction() {
        if appState.selectedTab == .list && coreLoop.hasPlan {
            appState.requestShoppingListAdd()
            return
        }

        if appState.selectedTab == .profile {
            withAnimation(ReasiMotion.tactileSpring) {
                appState.selectedTab = .home
            }
        }

        Task {
            await coreLoop.generateWeekPlan(
                store: appState.selectedStore,
                supabase: supabase,
                analytics: analytics,
                appState: appState,
                network: network
            )
        }
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
        .preferredColorScheme(.dark)
}
