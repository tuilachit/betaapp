import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network
    @Environment(OnboardingStore.self) private var onboarding

    @State private var showStorePicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                header
                planButton
                if coreLoop.generationState.isGenerating {
                    GenerationProgressCard(
                        stage: coreLoop.generationStage,
                        elapsedSeconds: coreLoop.generationElapsedSeconds,
                        cancel: { coreLoop.cancelGeneration(analytics: analytics) }
                    )
                }
                if let error = coreLoop.generationState.errorMessage {
                    generationErrorCard(error)
                }
                if let notice = coreLoop.generationState.noticeMessage {
                    generationNoticeCard(notice)
                }
                if coreLoop.isRestoringPlan {
                    SkeletonBlock(height: 178, radius: ReasiRadius.xl)
                } else if coreLoop.hasPlan {
                    featuredMealCard
                    currentPlanCard
                } else {
                    emptyPlanCard
                }
                if let restoreMessage = coreLoop.planRestoreMessage {
                    Text(restoreMessage)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                        .padding(ReasiSpacing.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                }
                storeCard
            }
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, 120)
        }
        .contentMargins(.horizontal, ReasiSpacing.s5, for: .scrollContent)
        .background(Color.reasi.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Choose store", isPresented: $showStorePicker, titleVisibility: .visible) {
            ForEach(FixtureStores.launchStores) { store in
                Button(store.name) {
                    selectStore(store)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reasi will keep your current list visible while it reorders item locations for this store.")
        }
        .task {
            analytics.capture(.coreHomeViewed)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text("Home")
                    .font(ReasiTypography.largeTitle)
                    .foregroundStyle(Color.reasi.text)
                Text("A calm week of meals, ready when you are.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
            }

            Spacer()

            Button {
                ReasiHaptics.light()
                appState.selectedTab = .profile
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(width: 54, height: 54)
                    .background(Color.reasi.surface, in: Circle())
                    .overlay {
                        Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                    }
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel("Open profile")
        }
    }

    private var planButton: some View {
        Button {
            Task {
                await coreLoop.generateWeekPlan(
                    store: appState.selectedStore,
                    supabase: supabase,
                    analytics: analytics,
                    appState: appState,
                    network: network
                )
            }
        } label: {
            HStack(spacing: ReasiSpacing.s3) {
                if coreLoop.generationState.isGenerating {
                    ProgressView()
                        .tint(Color.reasi.background)
                        .controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(planButtonTitle)
                    .lineLimit(1)
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
        .disabled(coreLoop.generationState.isGenerating)
        .opacity(coreLoop.generationState.isGenerating ? 0.86 : 1)
        .animation(ReasiMotion.fast, value: coreLoop.generationState)
    }

    private var planButtonTitle: String {
        if coreLoop.generationState.isGenerating {
            return "Planning your week"
        }
        return coreLoop.hasPlan ? "Plan a new week" : "Plan my week"
    }

    private var currentPlanCard: some View {
        Button {
            ReasiHaptics.light()
            appState.showPlan()
        } label: {
            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This week")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.muted)
                        Text(coreLoop.plan.weekLabel)
                            .font(ReasiTypography.title2)
                            .foregroundStyle(Color.reasi.text)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.reasi.dim)
                }

                Label(coreLoop.plan.storeName, systemImage: "storefront")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(
                        coreLoop.plan.storeId == appState.selectedStore.id
                            ? Color.reasi.muted
                            : Color.reasi.warning
                    )

                if coreLoop.plan.storeId != appState.selectedStore.id {
                    Text("This list is still arranged for \(coreLoop.plan.storeName).")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                }

                HStack(spacing: ReasiSpacing.s2) {
                    PillMetric(label: "\(coreLoop.plan.meals.count) dinners", symbol: "fork.knife")
                    PillMetric(label: "\(coreLoop.allShoppingItems.count) items", symbol: "checklist")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReasiSpacing.s5)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: 0x20251E),
                        Color.reasi.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
    }

    private var emptyPlanCard: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.reasi.textMuted)
            Text("No plan yet")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text("Your first generated week will appear here and stay linked to your account.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private func generationErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.reasi.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(coreLoop.hasPlan ? "Your existing week is safe" : "We couldn't start your week")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(message)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task {
                    await coreLoop.generateWeekPlan(
                        store: appState.selectedStore,
                        supabase: supabase,
                        analytics: analytics,
                        appState: appState,
                        network: network
                    )
                }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
            }
            .buttonStyle(ReasiPressStyle())
            .disabled(coreLoop.generationState.isGenerating)
        }
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private func generationNoticeCard(_ message: String) -> some View {
        Label {
            Text(message)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(Color.reasi.textMuted)
        }
        .padding(ReasiSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var storeCard: some View {
        Button {
            ReasiHaptics.light()
            showStorePicker = true
        } label: {
            HStack(spacing: ReasiSpacing.s3) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(width: 38, height: 38)
                    .background(Color.reasi.surfaceHigh, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Shopping at")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                    Text(appState.selectedStore.name)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.reasi.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
    }

    private func selectStore(_ store: StoreSummary) {
        let displayedStoreId = coreLoop.hasPlan ? coreLoop.plan.shoppingList.storeId : appState.selectedStore.id
        guard store.id != displayedStoreId || store.id != appState.selectedStore.id else { return }
        ReasiHaptics.selection()
        analytics.capture(.storeSelected, properties: [
            "store_id": .string(store.id.rawValue),
            "store_name": .string(store.name)
        ])
        coreLoop.requestStoreSwitch(
            to: store,
            appState: appState,
            supabase: supabase,
            analytics: analytics,
            completion: { _, confirmedStore in
                onboarding.applyConfirmedStore(confirmedStore)
            }
        )
    }

    @ViewBuilder
    private var featuredMealCard: some View {
        if let meal = coreLoop.plan.meals.first {
            Button {
                ReasiHaptics.light()
                appState.showPlan()
            } label: {
                HomeMealArtwork(meal: meal)
                    .frame(height: 220)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.84)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            Text(meal.day.uppercased())
                                .font(ReasiTypography.caption)
                                .foregroundStyle(.white.opacity(0.78))

                            Text(meal.dish)
                                .font(ReasiTypography.title2)
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            HStack(spacing: ReasiSpacing.s2) {
                                HomeMealMetric(label: "\(meal.cookTimeMin) min", symbol: "clock")
                                HomeMealMetric(label: meal.cuisine, symbol: "fork.knife")
                            }
                        }
                        .padding(ReasiSpacing.s5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                            .stroke(Color.reasi.border, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel(
                "\(meal.day), \(meal.dish), \(meal.cuisine), \(meal.cookTimeMin) minutes"
            )
            .accessibilityHint("Opens your week plan")
        }
    }
}

private struct HomeMealArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meal: MealSummary

    var body: some View {
        ZStack {
            Color.reasi.surfaceHigh

            if let imageURL = meal.imageUrl {
                AsyncImage(
                    url: imageURL,
                    transaction: Transaction(animation: reduceMotion ? nil : ReasiMotion.fast)
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty:
                        ProgressView()
                            .tint(Color.reasi.textMuted)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(Color.reasi.textMuted)
    }
}

private struct HomeMealMetric: View {
    let label: String
    let symbol: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(ReasiTypography.caption)
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, ReasiSpacing.s3)
            .padding(.vertical, ReasiSpacing.s2)
            .background(.black.opacity(0.45), in: Capsule())
    }
}

private struct PillMetric: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(ReasiTypography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Color.reasi.textMuted)
        .padding(.horizontal, ReasiSpacing.s3)
        .padding(.vertical, ReasiSpacing.s2)
        .background(Color.reasi.surfaceHigh, in: Capsule())
    }
}

#Preview {
    HomeView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .preferredColorScheme(.dark)
}
