import SwiftUI

struct WeekPlanPlaceholderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network
    @State private var selectedMeal: MealSummary?
    @State private var didTrackView = false
    @State private var arePlanNotesExpanded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                header
                if !coreLoop.recentPlans.isEmpty { recentPlans }

                if coreLoop.generationState.isGenerating {
                    generationLoading
                    if coreLoop.hasPlan {
                        planNotes
                        mealList
                        openShoppingListButton
                    }
                } else if !coreLoop.hasPlan {
                    if let error = coreLoop.generationState.errorMessage {
                        errorCard(error)
                    }
                    if let notice = coreLoop.generationState.noticeMessage {
                        noticeCard(notice)
                    }
                    emptyState
                } else {
                    if let error = coreLoop.generationState.errorMessage {
                        errorCard(error)
                    }
                    if let notice = coreLoop.generationState.noticeMessage {
                        noticeCard(notice)
                    }
                    planNotes
                    mealList
                    openShoppingListButton
                }
            }
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, 120)
        }
        .contentMargins(.horizontal, ReasiSpacing.s5, for: .scrollContent)
        .background(Color.reasi.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(meal: meal)
        }
        .task {
            guard !didTrackView else { return }
            didTrackView = true
            coreLoop.markWeekPlanViewed(analytics: analytics)
        }
        .task(id: coreLoop.plan.id) {
            await coreLoop.refreshRecentPlans(supabase: supabase)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            Text(coreLoop.hasPlan ? coreLoop.plan.kind.planHeading : "Your plans")
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
            Text(coreLoop.hasPlan ? planSubtitle : "No generated plan yet")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
        }
    }

    private var planSubtitle: String {
        let noun = coreLoop.plan.kind == .week ? "dinners" : "courses"
        return "\(coreLoop.plan.weekLabel) · \(coreLoop.plan.meals.count) \(noun)"
    }

    private var recentPlans: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ReasiSpacing.s2) {
                ForEach(coreLoop.recentPlans) { summary in
                    Button {
                        Task { await coreLoop.selectRecentPlan(id: summary.id, supabase: supabase) }
                    } label: {
                        HStack(spacing: ReasiSpacing.s2) {
                            Image(systemName: summary.kind == .week ? "calendar" : "sparkles")
                            Text(summary.name).lineLimit(1)
                        }
                        .font(ReasiTypography.caption)
                        .foregroundStyle(summary.id == coreLoop.plan.id ? Color.reasi.background : Color.reasi.textMuted)
                        .padding(.horizontal, ReasiSpacing.s3)
                        .frame(height: 36)
                        .background(summary.id == coreLoop.plan.id ? Color.reasi.text : Color.reasi.surface, in: Capsule())
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }
        }
    }

    private var generationLoading: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            GenerationProgressCard(
                stage: coreLoop.generationStage,
                elapsedSeconds: coreLoop.generationElapsedSeconds,
                isCancelling: coreLoop.generationState.isCancelling,
                cancel: {
                    coreLoop.cancelGeneration(
                        supabase: supabase,
                        analytics: analytics,
                        appState: appState
                    )
                }
            )

            if !coreLoop.hasPlan {
                VStack(spacing: ReasiSpacing.s3) {
                    ForEach(0..<7, id: \.self) { index in
                        SkeletonBlock(height: index == 0 ? 102 : 88, radius: ReasiRadius.lg)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func noticeCard(_ message: String) -> some View {
        Label(message, systemImage: "pause.circle.fill")
            .font(ReasiTypography.callout)
            .foregroundStyle(Color.reasi.textMuted)
            .padding(ReasiSpacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.reasi.warning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(coreLoop.hasPendingGeneration ? "Couldn't check progress" : "Planning didn't finish")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(error)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if let draft = appState.planBuilder.draft {
                    appState.openPlanBuilder(entryMethod: draft.entryMethod)
                } else {
                    coreLoop.startWeekPlanGeneration(
                        store: appState.selectedStore,
                        supabase: supabase,
                        analytics: analytics,
                        appState: appState,
                        network: network
                    )
                }
            } label: {
                Label(
                    coreLoop.hasPendingGeneration ? "Check status" : "Try again",
                    systemImage: "arrow.clockwise"
                )
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
            }
            .buttonStyle(ReasiPressStyle())
        }
        .padding(ReasiSpacing.s5)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
            Text("No plan yet")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text("Start with an idea, a product, or simply describe what you need.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)

            Button {
                Task {
                    appState.openPlanBuilder(entryMethod: .describe)
                }
            } label: {
                Label("Create a plan", systemImage: "sparkles")
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
    }

    private var planNotes: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack {
                Text("At a glance")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)

                Spacer()

                Label(coreLoop.plan.storeName, systemImage: "storefront")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)
            }

            HStack(spacing: ReasiSpacing.s2) {
                PlanMetric(
                    label: "\(coreLoop.plan.meals.count) \(coreLoop.plan.kind == .week ? "dinners" : "courses")",
                    symbol: "fork.knife"
                )
                PlanMetric(
                    label: "\(averageMealTime) min avg",
                    symbol: "clock"
                )
                PlanMetric(
                    label: estimatedWeekCost,
                    symbol: "banknote"
                )
            }

            if !coreLoop.plan.planningNotes.isEmpty {
                VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                    Text(coreLoop.plan.planningNotes)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .lineLimit(arePlanNotesExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        ReasiHaptics.light()
                        withAnimation(reduceMotion ? nil : ReasiMotion.tactileSpring) {
                            arePlanNotesExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(arePlanNotesExpanded ? "Show less" : "More details")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(arePlanNotesExpanded ? 180 : 0))
                        }
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.text)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ReasiPressStyle())
                    .accessibilityLabel(arePlanNotesExpanded ? "Collapse plan details" : "Expand plan details")
                }
            }
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
        .onChange(of: coreLoop.plan.id) { _, _ in
            arePlanNotesExpanded = false
        }
    }

    private var averageMealTime: Int {
        guard !coreLoop.plan.meals.isEmpty else { return 0 }
        let total = coreLoop.plan.meals.reduce(0) { result, meal in
            result + (meal.recipe?.totalTimeMin ?? meal.cookTimeMin)
        }
        return Int((Double(total) / Double(coreLoop.plan.meals.count)).rounded())
    }

    private var estimatedWeekCost: String {
        let total = coreLoop.plan.meals.reduce(0) { $0 + $1.costAud }
        return total.formatted(
            .currency(code: "AUD")
                .precision(.fractionLength(0))
        )
    }

    private var mealList: some View {
        VStack(spacing: ReasiSpacing.s3) {
            ForEach(Array(coreLoop.plan.meals.enumerated()), id: \.element.id) { index, meal in
                Button {
                    ReasiHaptics.light()
                    selectedMeal = meal
                } label: {
                    MealRow(meal: meal)
                }
                .buttonStyle(ReasiPressStyle())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(ReasiMotion.tactileSpring.delay(Double(index) * 0.025), value: coreLoop.plan.id)
            }
        }
    }

    private var openShoppingListButton: some View {
        Button {
            coreLoop.openShoppingList(appState: appState, analytics: analytics)
        } label: {
            HStack {
                Image(systemName: "checklist")
                Text("Open shopping list")
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
    }
}

private struct MealRow: View {
    let meal: MealSummary

    var body: some View {
        HStack(spacing: ReasiSpacing.s3) {
            MealArtwork(meal: meal)
                .frame(width: 96, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text(meal.day.uppercased())
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)

                Text(meal.dish)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                    .lineLimit(2)

                HStack(spacing: ReasiSpacing.s3) {
                    Label("\(meal.cookTimeMin) min", systemImage: "clock")
                    Label(
                        costLabel,
                        systemImage: "banknote"
                    )
                }
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.textMuted)

                Text(meal.cuisine)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)
            }

            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.reasi.dim)
        }
        .padding(ReasiSpacing.s3)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(meal.day), \(meal.dish), \(meal.cuisine), \(meal.cookTimeMin) minutes, estimated \(costLabel)"
        )
        .accessibilityHint("Opens recipe details")
    }

    private var costLabel: String {
        meal.costAud.formatted(
            .currency(code: "AUD")
                .precision(.fractionLength(0))
        )
    }
}

private struct PlanMetric: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(ReasiTypography.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(Color.reasi.textMuted)
        .padding(.horizontal, ReasiSpacing.s3)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color.reasi.surfaceHigh, in: Capsule())
    }
}

private struct MealDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: MealSummary

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                    hero
                    timeGrid
                    ingredients
                    method
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s5)
                .padding(.bottom, ReasiSpacing.s8)
            }
            .background(Color.reasi.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.reasi.text)
                            .frame(width: 34, height: 34)
                            .background(Color.reasi.surfaceHigh, in: Circle())
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            MealArtwork(meal: meal)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.76)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meal.day)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.textMuted)
                        Text(meal.dish)
                            .font(ReasiTypography.title)
                            .foregroundStyle(Color.reasi.text)
                            .minimumScaleFactor(0.82)
                            .lineLimit(2)
                    }
                    .padding(ReasiSpacing.s5)
                }

            if meal.imageUrl != nil {
                HStack(spacing: 4) {
                    Text("Photo")
                    if let photographerName = meal.imagePhotographerName,
                       let photographerUrl = meal.imagePhotographerUrl {
                        Text("by")
                        Link(photographerName, destination: photographerUrl)
                    }
                    if let sourceName = meal.imageSourceName,
                       let sourceUrl = meal.imageSourceUrl {
                        Text("on")
                        Link(sourceName, destination: sourceUrl)
                    }
                }
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            }

            Text(meal.description)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeGrid: some View {
        HStack(spacing: ReasiSpacing.s3) {
            DetailMetric(title: "Prep", value: "\(meal.recipe?.prepTimeMin ?? 10) min")
            DetailMetric(title: "Cook", value: "\(meal.recipe?.cookTimeMin ?? meal.cookTimeMin) min")
            DetailMetric(title: "Serves", value: "\(meal.recipe?.serves ?? 2)")
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("Ingredients")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)

            VStack(spacing: ReasiSpacing.s2) {
                ForEach(meal.recipe?.ingredients ?? []) { ingredient in
                    HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                        Circle()
                            .fill(Color.reasi.textMuted)
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name)
                                .font(ReasiTypography.bodyMedium)
                                .foregroundStyle(Color.reasi.text)
                            Text("\(ingredient.quantity) · \(ingredient.category)")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        }
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("Method")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)

            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                let steps = meal.recipe?.steps ?? [meal.description]
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                        Text("\(index + 1)")
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.background)
                            .frame(width: 24, height: 24)
                            .background(Color.reasi.text, in: Circle())
                        Text(step)
                            .font(ReasiTypography.body)
                            .foregroundStyle(Color.reasi.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        }
    }
}

private struct MealArtwork: View {
    let meal: MealSummary

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hexString: meal.tone) ?? Color.reasi.surfaceHigh,
                    Color.reasi.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let imageUrl = meal.imageUrl {
                AsyncImage(url: imageUrl, transaction: Transaction(animation: ReasiMotion.fast)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        Image(systemName: "fork.knife")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.reasi.text.opacity(0.65))
                    case .empty:
                        Color.reasi.surfaceHigh
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.reasi.textMuted)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .clipped()
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            Text(value)
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }
}

private extension Color {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

#Preview {
    WeekPlanPlaceholderView()
        .environment(AppState())
        .environment(CoreLoopStore())
        .environment(SupabaseService())
        .environment(AnalyticsService())
        .environment(NetworkMonitor())
        .preferredColorScheme(.dark)
}
