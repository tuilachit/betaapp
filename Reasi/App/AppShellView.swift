import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        ZStack(alignment: .bottom) {
            SlidingTabContent(selection: appState.selectedTab) { tab in
                tabStack(for: tab)
            }
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

    private var primaryActionSymbol: String {
        appState.selectedTab == .list && coreLoop.hasPlan ? "cart.badge.plus" : "plus"
    }

    private var primaryActionLabel: String {
        appState.selectedTab == .list && coreLoop.hasPlan
            ? "Add shopping item"
            : "Create a plan"
    }

    private func performPrimaryAction() {
        if appState.selectedTab == .list && coreLoop.hasPlan {
            appState.requestShoppingListAdd()
            return
        }

        appState.openPlanBuilder(entryMethod: .build)
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

private struct SlidingTabContent<Content: View>: View {
    let selection: AppTab
    let content: (AppTab) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var displayedTab: AppTab
    @State private var previousTab: AppTab

    init(selection: AppTab, @ViewBuilder content: @escaping (AppTab) -> Content) {
        self.selection = selection
        self.content = content
        _displayedTab = State(initialValue: selection)
        _previousTab = State(initialValue: selection)
    }

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                ZStack {
                    if displayedTab == tab {
                        content(tab)
                            .transition(TabSlideTransition(
                                tab: tab,
                                selection: selection,
                                previousSelection: previousTab,
                                reduceMotion: reduceMotion,
                                layoutDirection: layoutDirection
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(displayedTab == tab)
                .accessibilityHidden(displayedTab != tab)
                .zIndex(displayedTab == tab ? 1 : 0)
            }
        }
        .clipped()
        .animation(reduceMotion ? ReasiMotion.fast : ReasiMotion.tabTransition, value: displayedTab)
        .onChange(of: selection) { _, newTab in
            previousTab = displayedTab
            displayedTab = newTab
        }
    }

}

private struct TabSlideTransition: Transition {
    let tab: AppTab
    // The requested selection updates before displayedTab. This refreshes the
    // outgoing page's exit direction while it is still in the view hierarchy.
    let selection: AppTab
    let previousSelection: AppTab
    let reduceMotion: Bool
    let layoutDirection: LayoutDirection

    func body(content: Content, phase: TransitionPhase) -> some View {
        let tabs = AppTab.allCases
        let selectedIndex = tabs.firstIndex(of: selection) ?? 0
        let previousIndex = tabs.firstIndex(of: previousSelection) ?? 0
        let tabIndex = tabs.firstIndex(of: tab) ?? 0
        let direction: CGFloat = phase == .didDisappear
            ? (tabIndex < selectedIndex ? -1 : 1)
            : (selectedIndex > previousIndex ? 1 : -1)
        let layoutSign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1

        GeometryReader { geometry in
            content
                .offset(x: phase.isIdentity || reduceMotion ? 0 : direction * layoutSign * geometry.size.width)
                .opacity(phase.isIdentity ? 1 : 0)
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
