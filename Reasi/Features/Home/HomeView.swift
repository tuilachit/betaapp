import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

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
                if coreLoop.hasPlan {
                    tonightCard
                }
                #if DEBUG
                serviceStrip
                #endif
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
            Text("New meal plans use this store. Existing generated plans and lists keep the store they were created for.")
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

            Circle()
                .fill(Color.reasi.surface)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.reasi.text)
                }
                .overlay {
                    Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                }
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
                Text(coreLoop.generationState.isGenerating ? "Planning your week" : "Plan my week")
                    .lineLimit(1)
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
        .disabled(coreLoop.generationState.isGenerating)
        .opacity(coreLoop.generationState.isGenerating ? 0.86 : 1)
        .animation(ReasiMotion.fast, value: coreLoop.generationState)
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

                Text(coreLoop.plan.planningNotes)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Label(coreLoop.plan.storeName, systemImage: "storefront")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(
                        coreLoop.plan.storeId == appState.selectedStore.id
                            ? Color.reasi.muted
                            : Color.reasi.warning
                    )

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
            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                Text("Selected store")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.selectedStore.name)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                        Text("Grouped for \(appState.selectedStore.shortName)'s shop flow.")
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.reasi.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                    .stroke(Color.reasi.border, lineWidth: 1)
            }
        }
        .buttonStyle(ReasiPressStyle())
    }

    private func selectStore(_ store: StoreSummary) {
        guard store.id != appState.selectedStore.id else { return }
        withAnimation(ReasiMotion.tactileSpring) {
            appState.selectStore(store)
        }
        ReasiHaptics.selection()
        analytics.capture(.storeSelected, properties: [
            "store_id": .string(store.id.rawValue),
            "store_name": .string(store.name)
        ])
        Task {
            try? await supabase.saveSelectedStore(store.id)
        }
    }

    private var tonightCard: some View {
        let meal = coreLoop.plan.meals.first

        return VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Text("Tonight")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            Text(meal?.dish ?? "Plan your week")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text(meal?.description ?? "Create a plan to fill tonight's dinner.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let meal {
                HStack(spacing: ReasiSpacing.s2) {
                    PillMetric(label: "\(meal.cookTimeMin) min", symbol: "timer")
                    PillMetric(label: meal.cuisine, symbol: "globe.asia.australia")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    #if DEBUG
    private var serviceStrip: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("Services")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            ServiceStatusRow(status: supabase.status)
        }
    }
    #endif
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

#if DEBUG
private struct ServiceStatusRow: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Circle()
                .fill(status.state == .configured ? Color.reasi.success : Color.reasi.dim)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.text)
                Text(status.detail)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(2)
            }
            Spacer()
            Text(status.state.rawValue)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.textMuted)
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }
}
#endif

#Preview {
    HomeView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .preferredColorScheme(.dark)
}
