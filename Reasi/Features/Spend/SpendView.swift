import SwiftUI

struct SpendView: View {
    @Environment(AppState.self) private var appState
    @Environment(SpendingStore.self) private var spending
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var didTrackView = false
    @State private var showAllCategories = false
    @State private var showBudgetEditor = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
                header
                periodPicker
                content
            }
            .padding(.top, ReasiSpacing.s8)
            .padding(.bottom, 124)
        }
        .contentMargins(.horizontal, ReasiSpacing.s5, for: .scrollContent)
        .background(Color.reasi.background)
        .accessibilityIdentifier("spend-screen")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await spending.refresh(supabase: supabase)
        }
        .sheet(isPresented: $showBudgetEditor) {
            WeeklyBudgetEditor(
                currentBudget: onboarding.preferences.weeklyGroceryBudgetAud,
                onSave: saveBudget
            )
        }
        .task {
            if !didTrackView {
                didTrackView = true
                analytics.capture(.spendTabViewed, properties: [
                    "period": .string(spending.period.rawValue)
                ])
            }
            await spending.refresh(supabase: supabase)
        }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                    HStack {
                        Spacer()
                        ReasiProfileButton { appState.openProfile() }
                    }
                    headerCopy
                }
            } else {
                HStack(alignment: .center, spacing: ReasiSpacing.s4) {
                    headerCopy
                    Spacer(minLength: ReasiSpacing.s3)
                    ReasiProfileButton { appState.openProfile() }
                }
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            Text("Your spending")
                .font(dynamicTypeSize.isAccessibilitySize ? ReasiTypography.title : ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(periodSubtitle)
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var periodSubtitle: String {
        guard let dashboard = spending.dashboard else { return "Completed shops, clearly tracked" }
        return SpendingDateCopy.range(
            start: dashboard.startDate,
            endExclusive: dashboard.endDateExclusive
        )
    }

    private var periodPicker: some View {
        Picker("Spending period", selection: Binding(
            get: { spending.period },
            set: { newPeriod in
                Task {
                    await spending.selectPeriod(
                        newPeriod,
                        supabase: supabase,
                        analytics: analytics
                    )
                }
            }
        )) {
            ForEach(SpendingPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Spending period")
    }

    @ViewBuilder
    private var content: some View {
        if spending.isLoadingDashboard, spending.dashboard == nil {
            loadingState
        } else if let dashboard = spending.dashboard {
            if dashboard.hasCompletedShops {
                dashboardContent(dashboard)
            } else {
                emptyState(dashboard)
            }
        } else {
            unavailableState
        }
    }

    private var loadingState: some View {
        VStack(spacing: ReasiSpacing.s4) {
            SkeletonBlock(height: 210, radius: ReasiRadius.xl)
            SkeletonBlock(height: 90, radius: ReasiRadius.lg)
            SkeletonBlock(height: 180, radius: ReasiRadius.lg)
        }
    }

    private func dashboardContent(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s8) {
            spendingHero(dashboard)
            if let activeBasket = dashboard.activeBasket {
                projectedBasket(activeBasket)
            }
            categorySection(dashboard)
            insightSection(dashboard)
            if dashboard.period == .month, !dashboard.trend.isEmpty {
                monthTrend(dashboard)
            }
            recentShops(dashboard.recentTrips)
            if let message = spending.dashboardMessage {
                statusText(message)
            }
        }
    }

    private func spendingHero(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text(dashboard.period == .week ? "COMPLETED THIS WEEK" : "COMPLETED THIS MONTH")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                Text(dashboard.completedSpendAud, format: .currency(code: "AUD"))
                    .font(ReasiTypography.largeTitle)
                    .foregroundStyle(Color.reasi.text)
                    .contentTransition(.numericText(value: dashboard.completedSpendAud))
            }

            if dashboard.period == .week {
                weeklyBudgetStatus(dashboard)
            } else {
                HStack {
                    metricLabel(
                        "Weekly average",
                        value: dashboard.averageWeeklySpendAud?.formatted(.currency(code: "AUD")) ?? "-"
                    )
                    Spacer()
                    metricLabel("Price coverage", value: dashboard.priceCoverage.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .padding(ReasiSpacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.borderStrong, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func weeklyBudgetStatus(_ dashboard: SpendingDashboard) -> some View {
        if let budget = dashboard.weeklyBudgetAud,
           let remaining = dashboard.budgetRemainingAud,
           let progress = dashboard.budgetProgress {
            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.reasi.surfaceHigh)
                        Capsule()
                            .fill(remaining < 0 ? Color.reasi.warning : Color.reasi.success)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                            budgetTargetText(budget)
                            budgetRemainingText(remaining)
                        }
                    } else {
                        HStack {
                            budgetTargetText(budget)
                            Spacer()
                            budgetRemainingText(remaining)
                        }
                    }
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            }
        } else {
            Button {
                showBudgetEditor = true
            } label: {
                HStack {
                    Label("Set a weekly target", systemImage: "target")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
            }
            .buttonStyle(ReasiPressStyle())
        }
    }

    private func budgetTargetText(_ budget: Double) -> some View {
        Text("Target \(budget.formatted(.currency(code: "AUD")))")
    }

    private func budgetRemainingText(_ remaining: Double) -> some View {
        Text(remaining >= 0
             ? "\(remaining.formatted(.currency(code: "AUD"))) left"
             : "\(abs(remaining).formatted(.currency(code: "AUD"))) over")
            .foregroundStyle(remaining < 0 ? Color.reasi.warning : Color.reasi.textMuted)
    }

    private func projectedBasket(_ projection: ActiveBasketProjection) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                    projectedBasketLabel(projection)
                    Text(projection.projectedTotalAud, format: .currency(code: "AUD"))
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            } else {
                HStack(spacing: ReasiSpacing.s4) {
                    projectedBasketLabel(projection)
                    Spacer()
                    Text(projection.projectedTotalAud, format: .currency(code: "AUD"))
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            }
        }
        .padding(.vertical, ReasiSpacing.s2)
        .accessibilityElement(children: .combine)
    }

    private func projectedBasketLabel(_ projection: ActiveBasketProjection) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: "basket")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 42, height: 42)
                .background(Color.reasi.surfaceHigh, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Projected")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("Active basket · \(projection.pricedItems) of \(projection.totalItems) priced")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
    }

    private func categorySection(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            sectionHeader("Where it went", actionTitle: dashboard.categories.count > 3
                ? (showAllCategories ? "Less" : "All")
                : nil) {
                withAnimation(ReasiMotion.fast) { showAllCategories.toggle() }
            }

            if dashboard.categories.isEmpty {
                Text("Category totals will appear as more item prices are tracked.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
            } else {
                categoryBar(dashboard.categories)

                let visible = showAllCategories ? dashboard.categories : Array(dashboard.categories.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, category in
                        HStack {
                            Circle()
                                .fill(categoryColor(index))
                                .frame(width: 8, height: 8)
                            Text(category.label)
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.textMuted)
                            Spacer()
                            Text(category.amountAud, format: .currency(code: "AUD"))
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.text)
                        }
                        .padding(.vertical, ReasiSpacing.s3)
                        if index < visible.count - 1 {
                            Divider().overlay(Color.reasi.border)
                        }
                    }
                }
            }
        }
    }

    private func categoryBar(_ categories: [SpendingCategoryAmount]) -> some View {
        let visibleCategories = Array(categories.prefix(6))
        let total = max(visibleCategories.reduce(0) { $0 + $1.amountAud }, 0.01)
        return GeometryReader { proxy in
            let spacing: CGFloat = 2
            let availableWidth = max(0, proxy.size.width - spacing * CGFloat(max(visibleCategories.count - 1, 0)))
            HStack(spacing: 2) {
                ForEach(Array(visibleCategories.enumerated()), id: \.element.id) { index, category in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(categoryColor(index))
                        .frame(width: max(4, availableWidth * category.amountAud / total))
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func insightSection(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack {
                Text("Your shop, decoded")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                Spacer()
                if dashboard.insightStatus == "failed",
                   let tripId = dashboard.recentTrips.first?.tripId {
                    retryInsightButton(tripId: tripId)
                }
            }

            VStack(spacing: 0) {
                ForEach(dashboard.insightCards) { card in
                    NavigationLink(value: AppRoute.spendingInsight(card: card)) {
                        insightRow(card)
                    }
                    .buttonStyle(ReasiPressStyle())
                    if card.id != dashboard.insightCards.last?.id {
                        Divider().overlay(Color.reasi.border)
                    }
                }
            }
            .onAppear {
                for card in dashboard.insightCards {
                    analytics.capture(.spendingInsightViewed, properties: [
                        "kind": .string(card.kind.rawValue),
                        "period": .string(dashboard.period.rawValue)
                    ])
                }
            }
        }
    }

    private func retryInsightButton(tripId: String) -> some View {
        Button {
            Task {
                await spending.retryInsights(tripId: tripId, supabase: supabase)
            }
        } label: {
            if spending.isRetryingInsights {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.reasi.textMuted)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.reasi.surface, in: Circle())
            }
        }
        .buttonStyle(ReasiPressStyle())
        .disabled(spending.isRetryingInsights)
        .accessibilityLabel("Retry insights")
    }

    private func insightRow(_ card: SpendingInsightCard) -> some View {
        HStack(alignment: .center, spacing: ReasiSpacing.s4) {
            Image(systemName: card.kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.reasi.surface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(card.kind.label.uppercased())
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                Text(card.title)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.reasi.dim)
        }
        .padding(.vertical, ReasiSpacing.s3)
        .contentShape(Rectangle())
    }

    private func monthTrend(_ dashboard: SpendingDashboard) -> some View {
        let maximum = max(dashboard.trend.map(\.amountAud).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            sectionHeader("Weekly trend")
            HStack(alignment: .bottom, spacing: ReasiSpacing.s3) {
                ForEach(dashboard.trend) { point in
                    VStack(spacing: ReasiSpacing.s2) {
                        RoundedRectangle(cornerRadius: ReasiRadius.sm, style: .continuous)
                            .fill(Color.reasi.textMuted)
                            .frame(height: max(8, 84 * point.amountAud / maximum))
                        Text(SpendingDateCopy.shortDate(point.weekStart))
                            .font(ReasiTypography.navLabel)
                            .foregroundStyle(Color.reasi.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
        }
    }

    private func recentShops(_ trips: [SpendingRecentTrip]) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            sectionHeader("Recent shops")
            VStack(spacing: 0) {
                ForEach(trips) { trip in
                    Button {
                        appState.openSpendingTrip(trip.id)
                    } label: {
                        HStack(spacing: ReasiSpacing.s4) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.storeName)
                                    .font(ReasiTypography.headline)
                                    .foregroundStyle(Color.reasi.text)
                                    .lineLimit(1)
                                Text("\(SpendingDateCopy.dateTime(trip.completedAt)) · \(trip.checkedItems) items · \(trip.priceCoverage.formatted(.percent.precision(.fractionLength(0)))) priced")
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.muted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: ReasiSpacing.s3)
                            Text(trip.effectiveTotalAud, format: .currency(code: "AUD"))
                                .font(ReasiTypography.headline)
                                .foregroundStyle(Color.reasi.text)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.reasi.dim)
                        }
                        .padding(.vertical, ReasiSpacing.s4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ReasiPressStyle())
                    .accessibilityIdentifier("spend-recent-trip-\(trip.id)")
                    if trip.id != trips.last?.id {
                        Divider().overlay(Color.reasi.border)
                    }
                }
            }
        }
    }

    private func emptyState(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 58, height: 58)
                .background(Color.reasi.surface, in: Circle())

            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                Text("Your first recap starts here")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                Text("Finish a shop to see what you spent, where it went, and what to adjust next time.")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)
            }

            if let projection = dashboard.activeBasket {
                projectedBasket(projection)
            }

            Button {
                appState.showShoppingList()
            } label: {
                Label("Open shopping list", systemImage: "checklist")
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(.top, ReasiSpacing.s8)
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
            Text(spending.dashboardMessage ?? "Your spending could not load yet.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
            Button("Try again") {
                Task { await spending.refresh(supabase: supabase) }
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(.top, ReasiSpacing.s8)
    }

    private func sectionHeader(
        _ title: String,
        actionTitle: String? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        HStack {
            Text(title)
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .buttonStyle(ReasiPressStyle())
            }
        }
    }

    private func metricLabel(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            Text(label)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryColor(_ index: Int) -> Color {
        let colors: [Color] = [
            Color.reasi.success,
            Color(hex: 0x9FD8FF),
            Color.reasi.warning,
            Color(hex: 0xD8B4FE),
            Color(hex: 0xFFB4A2),
            Color.reasi.textMuted,
        ]
        return colors[index % colors.count]
    }

    private func saveBudget(_ value: Double?) async -> Bool {
        var updated = onboarding.preferences
        updated.weeklyGroceryBudgetAud = value
        do {
            try await supabase.saveSpendingPreferences(
                weeklyBudgetAud: value,
                coachTone: updated.spendingCoachTone
            )
            onboarding.updateProfilePreferences(updated)
            onboarding.markPreferencesSynced()
            analytics.capture(.weeklyBudgetSet, properties: [
                "has_budget": .bool(value != nil),
                "source": .string("spend")
            ])
            await spending.refresh(supabase: supabase)
            ReasiHaptics.success()
            return true
        } catch {
            ReasiHaptics.warning()
            return false
        }
    }
}

struct SpendingTripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpendingStore.self) private var spending
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let tripId: String

    @State private var showItems = false
    @State private var showTotalEditor = false
    @State private var didTrackView = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
                recapHeader
                if spending.isLoadingTrip, spending.selectedTrip?.trip.id != tripId {
                    loadingState
                } else if let detail = spending.selectedTrip, detail.trip.id == tripId {
                    recap(detail)
                } else {
                    unavailableState
                }
            }
            .padding(.horizontal, ReasiSpacing.s5)
            .padding(.top, ReasiSpacing.s5)
            .padding(.bottom, ReasiSpacing.s10)
        }
        .background(Color.reasi.background)
        .accessibilityIdentifier("spending-trip-detail")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showTotalEditor) {
            if let trip = spending.selectedTrip?.trip, trip.id == tripId {
                CheckoutTotalEditor(trip: trip) { total in
                    await spending.correctTotal(
                        tripId: tripId,
                        totalAud: total,
                        supabase: supabase,
                        analytics: analytics
                    )
                }
            }
        }
        .task(id: tripId) {
            if !didTrackView {
                didTrackView = true
                analytics.capture(.shoppingTripViewed, properties: ["trip_id": .string(tripId)])
            }
            await spending.loadTrip(id: tripId, supabase: supabase)
        }
    }

    private var recapHeader: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)
                    .frame(width: 44, height: 44)
                    .background(Color.reasi.surface, in: Circle())
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel("Back to spending")

            Text("Shop recap")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)

            Spacer()

            Menu {
                Button {
                    showTotalEditor = true
                } label: {
                    Label("Correct checkout total", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(width: 44, height: 44)
                    .background(Color.reasi.surface, in: Circle())
            }
            .accessibilityLabel("More recap options")
        }
    }

    private var loadingState: some View {
        VStack(spacing: ReasiSpacing.s4) {
            SkeletonBlock(height: 210, radius: ReasiRadius.xl)
            SkeletonBlock(height: 150, radius: ReasiRadius.lg)
            SkeletonBlock(height: 180, radius: ReasiRadius.lg)
        }
    }

    private func recap(_ detail: SpendingTripDetail) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s8) {
            recapHero(detail)
            recapBreakdown(detail)
            recapInsights(detail)
            purchasedItems(detail)
            if let message = spending.tripMessage {
                Text(message)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
    }

    private func recapHero(_ detail: SpendingTripDetail) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.trip.storeName)
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                Text(SpendingDateCopy.dateTime(detail.trip.completedAt))
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }

            Text(detail.trip.effectiveTotalAud, format: .currency(code: "AUD"))
                .font(ReasiTypography.largeTitle)
                .foregroundStyle(Color.reasi.text)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                        recapMetric("Items", "\(detail.trip.checkedItems)")
                        recapMetric("Price coverage", detail.trip.priceCoverage.formatted(.percent.precision(.fractionLength(0))))
                        recapMetric("Tracked", detail.trip.trackedTotalAud.formatted(.currency(code: "AUD")))
                    }
                } else {
                    HStack {
                        recapMetric("Items", "\(detail.trip.checkedItems)")
                        Spacer()
                        recapMetric("Price coverage", detail.trip.priceCoverage.formatted(.percent.precision(.fractionLength(0))))
                        Spacer()
                        recapMetric("Tracked", detail.trip.trackedTotalAud.formatted(.currency(code: "AUD")))
                    }
                }
            }

            if detail.trip.confirmedTotalAud != nil,
               abs(detail.trip.checkoutDifferenceAud) >= 0.01 {
                HStack {
                    Text("Checkout difference")
                    Spacer()
                    Text(detail.trip.checkoutDifferenceAud, format: .currency(code: "AUD").sign(strategy: .always()))
                }
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .padding(.top, ReasiSpacing.s2)
            }

            if let remaining = detail.trip.weeklyBudgetRemainingAud {
                Divider().overlay(Color.reasi.border)
                Text(remaining >= 0
                     ? "\(remaining.formatted(.currency(code: "AUD"))) remains in this week's target."
                     : "This week is \(abs(remaining).formatted(.currency(code: "AUD"))) over target.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(remaining < 0 ? Color.reasi.warning : Color.reasi.textMuted)
            }
        }
        .padding(ReasiSpacing.s6)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.borderStrong, lineWidth: 1)
        }
    }

    private func recapBreakdown(_ detail: SpendingTripDetail) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Text("What shaped the shop")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: ReasiSpacing.s3) {
                        breakdownMetric("Planned", amount: detail.plannedSpendAud, color: Color.reasi.success)
                        breakdownMetric("Added", amount: detail.addedSpendAud, color: Color.reasi.warning)
                    }
                } else {
                    HStack(spacing: ReasiSpacing.s3) {
                        breakdownMetric("Planned", amount: detail.plannedSpendAud, color: Color.reasi.success)
                        breakdownMetric("Added", amount: detail.addedSpendAud, color: Color.reasi.warning)
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(detail.categories.prefix(4)) { category in
                    HStack {
                        Text(category.label)
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                        Spacer()
                        Text(category.amountAud, format: .currency(code: "AUD"))
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.text)
                    }
                    .padding(.vertical, ReasiSpacing.s3)
                    if category.id != detail.categories.prefix(4).last?.id {
                        Divider().overlay(Color.reasi.border)
                    }
                }
            }
        }
    }

    private func recapInsights(_ detail: SpendingTripDetail) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack {
                Text("Three takeaways")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                Spacer()
                if detail.insightStatus == "pending" || detail.insightStatus == "missing" {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.reasi.textMuted)
                        .accessibilityLabel("Refreshing insights")
                } else if detail.insightStatus == "failed" {
                    retryInsightButton(tripId: detail.trip.id)
                }
            }

            ForEach(detail.insightCards) { card in
                NavigationLink(value: AppRoute.spendingInsight(card: card)) {
                    HStack(alignment: .top, spacing: ReasiSpacing.s4) {
                        Text(card.kind.label)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.muted)
                            .frame(width: 82, alignment: .leading)
                        Text(card.title)
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.reasi.dim)
                    }
                    .padding(.vertical, ReasiSpacing.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReasiPressStyle())
            }
            .onAppear {
                for card in detail.insightCards {
                    analytics.capture(.spendingInsightViewed, properties: [
                        "kind": .string(card.kind.rawValue),
                        "source": .string("trip_recap")
                    ])
                }
            }
        }
    }

    private func retryInsightButton(tripId: String) -> some View {
        Button {
            Task {
                await spending.retryInsights(tripId: tripId, supabase: supabase)
            }
        } label: {
            if spending.isRetryingInsights {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.reasi.textMuted)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.reasi.surface, in: Circle())
            }
        }
        .buttonStyle(ReasiPressStyle())
        .disabled(spending.isRetryingInsights)
        .accessibilityLabel("Retry insights")
    }

    private func purchasedItems(_ detail: SpendingTripDetail) -> some View {
        DisclosureGroup(isExpanded: $showItems) {
            VStack(spacing: 0) {
                ForEach(detail.items.filter(\.checked)) { item in
                    HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.text)
                            Text([item.quantity, item.spendCategory].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                        }
                        Spacer()
                        if let price = item.priceAud {
                            Text(price, format: .currency(code: "AUD"))
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.textMuted)
                        } else {
                            Text("Not priced")
                                .font(ReasiTypography.caption)
                                .foregroundStyle(Color.reasi.muted)
                        }
                    }
                    .padding(.vertical, ReasiSpacing.s3)
                    Divider().overlay(Color.reasi.border)
                }
            }
            .padding(.top, ReasiSpacing.s3)
        } label: {
            Text("Purchased items")
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
        }
        .tint(Color.reasi.textMuted)
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            Text(spending.tripMessage ?? "This shop could not load yet.")
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
            Button("Try again") {
                Task { await spending.loadTrip(id: tripId, supabase: supabase) }
            }
            .buttonStyle(ReasiPrimaryButtonStyle())
        }
        .padding(.top, ReasiSpacing.s8)
    }

    private func recapMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            Text(label)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
        }
    }

    private func breakdownMetric(_ label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 28, height: 4)
            Text(amount, format: .currency(code: "AUD"))
                .font(ReasiTypography.title2)
                .foregroundStyle(Color.reasi.text)
            Text(label)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
        }
        .padding(ReasiSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }
}

struct SpendingInsightDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AnalyticsService.self) private var analytics
    let card: SpendingInsightCard

    @State private var didTrackExpansion = false

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.reasi.text)
                    .frame(width: 44, height: 44)
                    .background(Color.reasi.surface, in: Circle())
            }
            .buttonStyle(ReasiPressStyle())
            .accessibilityLabel("Back")

            Text(card.kind.label)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
            Text(card.title)
                .font(ReasiTypography.title)
                .foregroundStyle(Color.reasi.text)
            Text(card.body)
                .font(ReasiTypography.body)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.reasi.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didTrackExpansion else { return }
            didTrackExpansion = true
            analytics.capture(.spendingInsightExpanded, properties: [
                "kind": .string(card.kind.rawValue)
            ])
        }
    }
}

private struct WeeklyBudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSave: (Double?) async -> Bool

    init(currentBudget: Double?, onSave: @escaping (Double?) async -> Bool) {
        _amountText = State(initialValue: currentBudget.map { String(format: "%.0f", $0) } ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                Text("A weekly target makes the Spend view easier to read. You can change it anytime.")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)

                HStack(alignment: .firstTextBaseline, spacing: ReasiSpacing.s2) {
                    Text("A$")
                        .font(ReasiTypography.title2)
                        .foregroundStyle(Color.reasi.textMuted)
                    TextField("120", text: $amountText)
                        .font(ReasiTypography.largeTitle)
                        .foregroundStyle(Color.reasi.text)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Weekly grocery target")
                }
                .padding(.vertical, ReasiSpacing.s4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.reasi.borderStrong).frame(height: 1)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(Color.reasi.background) }
                        Text(isSaving ? "Saving" : "Save target")
                    }
                }
                .buttonStyle(ReasiPrimaryButtonStyle())
                .disabled(isSaving)

                if !amountText.isEmpty {
                    Button("Remove target") {
                        Task {
                            isSaving = true
                            if await onSave(nil) { dismiss() }
                            isSaving = false
                        }
                    }
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(ReasiPressStyle())
                }
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.background)
            .navigationTitle("Weekly target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func save() {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value <= 10_000 else {
            errorMessage = "Enter a weekly amount between A$1 and A$10,000."
            return
        }
        Task {
            isSaving = true
            errorMessage = nil
            if await onSave(value) {
                dismiss()
            } else {
                errorMessage = "The target could not be saved. Check your connection and try again."
            }
            isSaving = false
        }
    }
}

private struct CheckoutTotalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let trip: SpendingTrip
    let onSave: (Double) async -> Bool

    init(trip: SpendingTrip, onSave: @escaping (Double) async -> Bool) {
        self.trip = trip
        self.onSave = onSave
        _amountText = State(initialValue: String(format: "%.2f", trip.effectiveTotalAud))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                Text("Use the final checkout total when it differs from the tracked item prices.")
                    .font(ReasiTypography.body)
                    .foregroundStyle(Color.reasi.textMuted)

                HStack(alignment: .firstTextBaseline, spacing: ReasiSpacing.s2) {
                    Text("A$")
                        .font(ReasiTypography.title2)
                        .foregroundStyle(Color.reasi.textMuted)
                    TextField("0.00", text: $amountText)
                        .font(ReasiTypography.largeTitle)
                        .foregroundStyle(Color.reasi.text)
                        .keyboardType(.decimalPad)
                }
                .padding(.vertical, ReasiSpacing.s4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.reasi.borderStrong).frame(height: 1)
                }

                Text("Tracked items: \(trip.trackedTotalAud.formatted(.currency(code: "AUD")))")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)

                if let errorMessage {
                    Text(errorMessage)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(Color.reasi.background) }
                        Text(isSaving ? "Updating" : "Update total")
                    }
                }
                .buttonStyle(ReasiPrimaryButtonStyle())
                .disabled(isSaving)
            }
            .padding(ReasiSpacing.s5)
            .background(Color.reasi.background)
            .navigationTitle("Checkout total")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func save() {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0, value <= 999_999.99 else {
            errorMessage = "Enter a valid checkout total."
            return
        }
        Task {
            isSaving = true
            errorMessage = nil
            if await onSave(value) {
                dismiss()
            } else {
                errorMessage = "The total could not be updated. Please try again."
            }
            isSaving = false
        }
    }
}

private enum SpendingDateCopy {
    static func range(start: String, endExclusive: String) -> String {
        guard let startDate = dateOnly(start),
              let endDate = dateOnly(endExclusive).flatMap({ Calendar.current.date(byAdding: .day, value: -1, to: $0) }) else {
            return "Completed shops"
        }
        return "\(startDate.formatted(.dateTime.day().month(.abbreviated))) - \(endDate.formatted(.dateTime.day().month(.abbreviated)))"
    }

    static func shortDate(_ value: String) -> String {
        dateOnly(value)?.formatted(.dateTime.day().month(.abbreviated)) ?? value
    }

    static func dateTime(_ value: String) -> String {
        value.reasiISODate?.formatted(date: .abbreviated, time: .omitted) ?? value
    }

    private static func dateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
