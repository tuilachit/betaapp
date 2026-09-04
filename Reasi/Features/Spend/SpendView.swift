import SwiftUI
import Charts

struct SpendView: View {
    @Environment(AppState.self) private var appState
    @Environment(SpendingStore.self) private var spending
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var didTrackView = false
    @State private var selectedCategoryID: String?
    @State private var showMoreInsights = false
    @State private var trackedInsightIDs: Set<String> = []
    @State private var showBudgetEditor = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                header
                periodPicker
                content
            }
            .padding(.top, ReasiSpacing.s3)
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
            Text("Spend")
                .font(ReasiTypography.title2)
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
                selectedCategoryID = nil
                showMoreInsights = false
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
        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
            spendingHero(dashboard)
            categorySection(dashboard)
            insightSection(dashboard)
            if let activeBasket = dashboard.activeBasket {
                projectedBasket(activeBasket)
            }
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
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text(dashboard.period == .week ? "THIS WEEK" : "THIS MONTH")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        completedSpendText(dashboard)
                        Text("spent")
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.textMuted)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: ReasiSpacing.s2) {
                        completedSpendText(dashboard)
                        Text("spent")
                            .font(ReasiTypography.headline)
                            .foregroundStyle(Color.reasi.textMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if dashboard.period == .week {
                weeklyBudgetStatus(dashboard)
            } else if let average = dashboard.averageWeeklySpendAud {
                Text("\(average.formatted(.currency(code: "AUD"))) average per week")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
            } else {
                Text("Your weekly average will appear after more completed shops.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedSpendText(_ dashboard: SpendingDashboard) -> some View {
        Text(dashboard.completedSpendAud, format: .currency(code: "AUD"))
            .font(ReasiTypography.largeTitle)
            .foregroundStyle(Color.reasi.text)
            .contentTransition(.numericText(value: dashboard.completedSpendAud))
    }

    @ViewBuilder
    private func weeklyBudgetStatus(_ dashboard: SpendingDashboard) -> some View {
        if let budget = dashboard.weeklyBudgetAud,
           let remaining = dashboard.budgetRemainingAud,
           let progress = dashboard.budgetProgress {
            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                HStack(spacing: ReasiSpacing.s2) {
                    Text(remaining >= 0
                         ? "\(remaining.formatted(.currency(code: "AUD"))) left of \(budget.formatted(.currency(code: "AUD")))"
                         : "\(abs(remaining).formatted(.currency(code: "AUD"))) over \(budget.formatted(.currency(code: "AUD")))")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(remaining < 0 ? Color.reasi.warning : Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ReasiSpacing.s2)
                    Button {
                        showBudgetEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.reasi.textMuted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(ReasiPressStyle())
                    .accessibilityLabel("Edit weekly target")
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.reasi.border)
                        Capsule()
                            .fill(remaining < 0 ? Color.reasi.warning : Color.reasi.success)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 5)
                .accessibilityLabel("Weekly target progress")
                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
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

    private func projectedBasket(_ projection: ActiveBasketProjection) -> some View {
        HStack(spacing: ReasiSpacing.s4) {
            Image(systemName: "basket")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Projected basket")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                Text("\(projection.pricedItems) of \(projection.totalItems) priced")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
            Spacer(minLength: ReasiSpacing.s3)
            Text(projection.projectedTotalAud, format: .currency(code: "AUD"))
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.textMuted)
        }
        .padding(.vertical, ReasiSpacing.s3)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.reasi.border)
        }
        .accessibilityElement(children: .combine)
    }

    private func categorySection(_ dashboard: SpendingDashboard) -> some View {
        let breakdown = SpendCategoryBreakdown(categories: dashboard.categories)

        return VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            sectionHeader("Where it went")

            if breakdown.slices.isEmpty {
                VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                    Text("Not enough priced items yet")
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text("Category totals will appear as item prices are tracked.")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.muted)
                }
                .padding(.vertical, ReasiSpacing.s3)
            } else {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: ReasiSpacing.s5) {
                            categoryDonut(breakdown)
                                .frame(maxWidth: .infinity)
                            categoryLegend(breakdown)
                        }
                    } else {
                        HStack(alignment: .center, spacing: ReasiSpacing.s5) {
                            categoryDonut(breakdown)
                            categoryLegend(breakdown)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            categoryTrustCopy(dashboard)
        }
        .onChange(of: breakdown.slices.map(\.id)) {
            if breakdown.slice(id: selectedCategoryID) == nil {
                selectedCategoryID = nil
            }
        }
    }

    private func categoryDonut(_ breakdown: SpendCategoryBreakdown) -> some View {
        let selected = breakdown.slice(id: selectedCategoryID)

        return ZStack {
            Chart(breakdown.slices) { slice in
                SectorMark(
                    angle: .value("Tracked spend", slice.amountAud),
                    innerRadius: .ratio(0.64),
                    angularInset: 2
                )
                .cornerRadius(4)
                .foregroundStyle(categoryColor(slice.colorRole))
                .opacity(selected == nil || selected?.id == slice.id ? 1 : 0.38)
            }
            .chartLegend(.hidden)
            .chartGesture { proxy in
                SpatialTapGesture()
                    .onEnded { event in
                        let angle = proxy.angle(at: event.location)
                        let value = proxy.value(atAngle: angle, as: Double.self)
                        if let slice = breakdown.slice(atCumulativeValue: value) {
                            selectedCategoryID = slice.id
                            ReasiHaptics.selection()
                        }
                    }
            }

            VStack(spacing: 2) {
                Text(selected?.label.uppercased() ?? "TRACKED")
                    .font(ReasiTypography.navLabel)
                    .foregroundStyle(Color.reasi.muted)
                    .lineLimit(1)
                Text(selected?.amountAud ?? breakdown.totalAud, format: .currency(code: "AUD"))
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                    .contentTransition(.numericText())
                if let selected {
                    Text(selected.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                } else {
                    Text("spend")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                }
            }
            .padding(.horizontal, ReasiSpacing.s3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: 144, height: 144)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("spend-category-chart")
        .accessibilityLabel("Tracked spending by category")
        .accessibilityValue(categoryAccessibilitySummary(breakdown))
    }

    private func categoryLegend(_ breakdown: SpendCategoryBreakdown) -> some View {
        let selected = breakdown.slice(id: selectedCategoryID)

        return VStack(spacing: ReasiSpacing.s1) {
            ForEach(breakdown.slices) { slice in
                Button {
                    if selected?.id == slice.id {
                        selectedCategoryID = nil
                    } else {
                        selectedCategoryID = slice.id
                        ReasiHaptics.selection()
                    }
                } label: {
                    HStack(spacing: ReasiSpacing.s2) {
                        Circle()
                            .fill(categoryColor(slice.colorRole))
                            .frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.textMuted)
                            .lineLimit(1)
                        Spacer(minLength: ReasiSpacing.s2)
                        Text(slice.amountAud, format: .currency(code: "AUD"))
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.text)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReasiPressStyle())
                .accessibilityIdentifier("spend-category-legend-\(categoryAccessibilityID(slice.label))")
                .accessibilityLabel("\(slice.label), \(slice.amountAud.formatted(.currency(code: "AUD"))), \(slice.fraction.formatted(.percent.precision(.fractionLength(0))))")
                .accessibilityValue(selected?.id == slice.id ? "Selected" : "Not selected")
            }
        }
    }

    private func categoryTrustCopy(_ dashboard: SpendingDashboard) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s1) {
            categoryCoverageText(dashboard)
            checkoutDifferenceText(dashboard)
        }
        .accessibilityElement(children: .combine)
    }

    private func categoryCoverageText(_ dashboard: SpendingDashboard) -> some View {
        Text("Based on \(dashboard.pricedCheckedItems) of \(dashboard.checkedItems) priced items")
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)
    }

    @ViewBuilder
    private func checkoutDifferenceText(_ dashboard: SpendingDashboard) -> some View {
        if abs(dashboard.checkoutDifferenceAud) >= 0.01 {
            Text("\(abs(dashboard.checkoutDifferenceAud).formatted(.currency(code: "AUD"))) checkout difference excluded")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.warning)
        }
    }

    private func categoryAccessibilitySummary(_ breakdown: SpendCategoryBreakdown) -> String {
        breakdown.slices.map { slice in
            "\(slice.label) \(slice.fraction.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: ", ")
    }

    private func categoryAccessibilityID(_ label: String) -> String {
        label.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }.reduce(into: "") { result, character in
            if character != "-" || result.last != "-" {
                result.append(character)
            }
        }
    }

    private func insightSection(_ dashboard: SpendingDashboard) -> some View {
        let primary = dashboard.insightCards.first(where: { $0.kind == .nextAction })
        let supporting = [SpendingInsightKind.pattern, .context].compactMap { kind in
            dashboard.insightCards.first(where: { $0.kind == kind })
        }

        return VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack {
                Text("Next shop")
                    .font(ReasiTypography.title2)
                    .foregroundStyle(Color.reasi.text)
                Spacer()
                if dashboard.insightStatus == "failed",
                   let tripId = dashboard.recentTrips.first?.tripId {
                    retryInsightButton(tripId: tripId)
                }
            }

            if let primary {
                NavigationLink(value: AppRoute.spendingInsight(card: primary)) {
                    insightRow(primary, showsBody: true)
                }
                .buttonStyle(ReasiPressStyle())
                .accessibilityIdentifier("spend-next-action")
                .onAppear {
                    trackInsight(primary, period: dashboard.period)
                }
            } else if dashboard.insightStatus == "pending" || dashboard.insightStatus == "in_progress" {
                HStack(spacing: ReasiSpacing.s3) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.reasi.textMuted)
                    Text("Finding one useful change for your next shop...")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.muted)
                }
                .padding(.vertical, ReasiSpacing.s3)
            } else {
                Text("Your next recommendation will appear after another completed shop.")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.muted)
                    .padding(.vertical, ReasiSpacing.s3)
            }

            if !supporting.isEmpty {
                Button {
                    if reduceMotion {
                        showMoreInsights.toggle()
                    } else {
                        withAnimation(ReasiMotion.fast) {
                            showMoreInsights.toggle()
                        }
                    }
                } label: {
                    HStack {
                        Text(showMoreInsights ? "Hide insights" : "More insights")
                        Spacer()
                        Image(systemName: showMoreInsights ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReasiPressStyle())
                .accessibilityIdentifier("spend-more-insights")
                .accessibilityValue(showMoreInsights ? "Expanded" : "Collapsed")

                if showMoreInsights {
                    VStack(spacing: 0) {
                        ForEach(supporting) { card in
                            Divider().overlay(Color.reasi.border)
                            NavigationLink(value: AppRoute.spendingInsight(card: card)) {
                                insightRow(card)
                            }
                            .buttonStyle(ReasiPressStyle())
                            .onAppear {
                                trackInsight(card, period: dashboard.period)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func trackInsight(_ card: SpendingInsightCard, period: SpendingPeriod) {
        let trackingID = "\(period.rawValue):\(card.id)"
        guard !trackedInsightIDs.contains(trackingID) else { return }
        trackedInsightIDs.insert(trackingID)
        analytics.capture(.spendingInsightViewed, properties: [
            "kind": .string(card.kind.rawValue),
            "period": .string(period.rawValue)
        ])
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

    private func insightRow(_ card: SpendingInsightCard, showsBody: Bool = false) -> some View {
        HStack(alignment: .center, spacing: ReasiSpacing.s4) {
            Image(systemName: card.kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 40, height: 40)
                .background(Color.reasi.surface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                if !showsBody {
                    Text(card.kind.label.uppercased())
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
                Text(card.title)
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                    .lineLimit(2)
                if showsBody {
                    Text(card.body)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                                Text(SpendingDateCopy.dateTime(trip.completedAt))
                                    .font(ReasiTypography.caption)
                                    .foregroundStyle(Color.reasi.muted)
                                    .lineLimit(1)
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

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryColor(_ role: SpendCategoryColorRole) -> Color {
        switch role {
        case .produce: Color(hex: 0x9FE3B1)
        case .protein: Color(hex: 0xFF9A8B)
        case .pantry: Color(hex: 0xC5A9FF)
        case .dairy: Color(hex: 0xFFD36A)
        case .bakery: Color(hex: 0xF5B97A)
        case .frozen: Color(hex: 0x88C9FF)
        case .drinks: Color(hex: 0x7ADFD6)
        case .baby: Color(hex: 0xF3A8D3)
        case .personalCare: Color(hex: 0xE89AAE)
        case .household: Color(hex: 0xA8B6FF)
        case .other: Color.reasi.textMuted
        case .accentA: Color(hex: 0xB2E0FF)
        case .accentB: Color(hex: 0xE1B8FF)
        case .accentC: Color(hex: 0xFFC6A5)
        }
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
