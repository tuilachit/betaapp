import PhotosUI
import SwiftUI
import UIKit

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
                creationActions
                if coreLoop.generationState.isGenerating {
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

    private var creationActions: some View {
        VStack(spacing: ReasiSpacing.s3) {
            Button {
                analytics.capture(.planBuilderOpened, properties: ["entry_method": .string(EntryMethod.describe.rawValue)])
                appState.openPlanBuilder(entryMethod: .describe)
            } label: {
                Label("Describe a plan", systemImage: "sparkles")
            }
            .buttonStyle(ReasiPrimaryButtonStyle())

            Button {
                analytics.capture(.planBuilderOpened, properties: ["entry_method": .string(EntryMethod.build.rawValue)])
                appState.openPlanBuilder(entryMethod: .build)
            } label: {
                Label("Add ideas or products", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(Color.reasi.text)
                    .background(Color.reasi.surface, in: Capsule())
                    .overlay { Capsule().stroke(Color.reasi.borderStrong, lineWidth: 1) }
            }
            .buttonStyle(ReasiPressStyle())
        }
        .disabled(coreLoop.generationState.isGenerating)
        .opacity(coreLoop.generationState.isGenerating ? 0.72 : 1)
    }

    private var currentPlanCard: some View {
        Button {
            ReasiHaptics.light()
            appState.showPlan()
        } label: {
            VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coreLoop.plan.kind == .week ? "This week" : "Your occasion")
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
                    PillMetric(
                        label: "\(coreLoop.plan.meals.count) \(coreLoop.plan.kind == .week ? "dinners" : "courses")",
                        symbol: "fork.knife"
                    )
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

struct PlanBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(CoreLoopStore.self) private var coreLoop
    @Environment(SupabaseService.self) private var supabase
    @Environment(AnalyticsService.self) private var analytics
    @Environment(NetworkMonitor.self) private var network

    let entryMethod: EntryMethod

    @State private var brief: PlanBrief
    @State private var newIdea = ""
    @State private var clarificationAnswer = ""
    @State private var interpretation: PlanInterpretation?
    @State private var isInterpreting = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var productSearchContext: ProductSearchContext?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var photoMode: BuilderPhotoMode = .meal
    @State private var showsDiscardConfirmation = false
    @FocusState private var ideaFieldFocused: Bool

    init(entryMethod: EntryMethod) {
        self.entryMethod = entryMethod
        _brief = State(initialValue: PlanBrief(
            kind: entryMethod == .describe ? .occasion : .week,
            entryMethod: entryMethod
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                    intro
                    planControls
                    ideaComposer
                    if !brief.ideas.isEmpty { ideasSection }
                    if let interpretation { interpretationSection(interpretation) }
                    budgetSection
                    submitButton
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s4)
                .padding(.bottom, ReasiSpacing.s10)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.reasi.background)
            .navigationTitle("Build your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Discard", role: .destructive) { showsDiscardConfirmation = true }
                        .foregroundStyle(Color.reasi.warning)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            appState.planBuilder.begin(entryMethod: entryMethod)
            if let restored = appState.planBuilder.draft {
                brief = restored
            }
            if entryMethod == .describe { ideaFieldFocused = true }
        }
        .onChange(of: brief) { _, updated in
            appState.planBuilder.update(updated)
        }
        .onChange(of: brief.kind) { oldKind, newKind in
            if newKind == .week {
                brief.desiredCount = 7
            } else if brief.desiredCount == oldKind.defaultDesiredCount {
                brief.desiredCount = newKind.defaultDesiredCount
            } else {
                brief.desiredCount = min(5, max(2, brief.desiredCount))
            }
        }
        .confirmationDialog("Discard this plan?", isPresented: $showsDiscardConfirmation) {
            Button("Discard draft", role: .destructive) {
                appState.planBuilder.discard()
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your ideas will be removed from this device.")
        }
        .fullScreenCover(item: $productSearchContext) { context in
            ProductSearchView(
                context: context,
                store: appState.selectedStore,
                recentCandidates: [],
                searchProducts: { query in
                    try await supabase.searchProducts(query: query, storeId: appState.selectedStore.id)
                },
                importProductLink: { url in
                    try await supabase.resolveProduct(
                        input: ResolveProductInput(
                            method: "link",
                            storeId: appState.selectedStore.id,
                            query: nil,
                            url: url,
                            uploadPath: nil
                        )
                    ).candidates
                },
                resolveBarcode: { barcode in
                    try await supabase.resolveProduct(
                        input: ResolveProductInput(
                            method: "barcode",
                            storeId: appState.selectedStore.id,
                            query: nil,
                            url: nil,
                            uploadPath: nil,
                            barcode: barcode
                        )
                    ).candidates
                },
                addCandidate: { candidate, _ in
                    await MainActor.run { addProduct(candidate) }
                    return true
                },
                addManualItem: { value in
                    await MainActor.run { addIdea(title: value, type: .listItem) }
                    return true
                }
            )
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await processPhoto(item) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
            Text(entryMethod == .describe ? "What are you planning?" : "Start with anything you have")
                .font(ReasiTypography.title)
                .foregroundStyle(Color.reasi.text)
            Text("Meals, products and rough ideas can live together. You stay in control before Reasi plans.")
                .font(ReasiTypography.callout)
                .foregroundStyle(Color.reasi.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planControls: some View {
        VStack(spacing: ReasiSpacing.s4) {
            Picker("Plan type", selection: $brief.kind) {
                ForEach(PlanKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: ReasiSpacing.s3) {
                Stepper("Serves \(brief.serves)", value: $brief.serves, in: 1...12)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                if brief.kind == .occasion {
                    DatePicker(
                        "When",
                        selection: Binding(
                            get: { brief.occasionAt ?? Date() },
                            set: { brief.occasionAt = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }
            }

            if brief.kind == .week {
                Label("7 dinners", systemImage: "calendar")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Stepper(
                    "\(brief.desiredCount) courses",
                    value: $brief.desiredCount,
                    in: 2...5
                )
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var ideaComposer: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            TextField(
                brief.kind == .occasion ? "e.g. romantic dinner, salmon pasta..." : "e.g. quick dinners, tacos, chicken...",
                text: $newIdea,
                axis: .vertical
            )
            .font(ReasiTypography.body)
            .foregroundStyle(Color.reasi.text)
            .focused($ideaFieldFocused)
            .lineLimit(2...5)
            .padding(ReasiSpacing.s4)
            .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
            .submitLabel(.done)

            HStack(spacing: ReasiSpacing.s2) {
                Button { Task { await addTypedInput() } } label: {
                    Label(
                        isResolving ? "Adding" : (entryMethod == .describe ? "Add to brief" : "Add idea"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(ReasiPressStyle())
                .disabled(newIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)

                Spacer()

                Menu {
                    Button("Search or scan product", systemImage: "barcode.viewfinder") {
                        productSearchContext = ProductSearchContext(
                            targetItemID: nil,
                            targetItemName: nil,
                            initialQuery: ""
                        )
                    }
                    Button("Food or recipe photo", systemImage: "fork.knife") { pickPhoto(.meal) }
                    Button("Product photo", systemImage: "shippingbox") { pickPhoto(.product) }
                    Button("Handwritten list", systemImage: "text.viewfinder") { pickPhoto(.handwrittenList) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.reasi.text)
                }
                .accessibilityLabel("More ways to add")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.warning)
            }
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            Text("In this plan")
                .font(ReasiTypography.headline)
                .foregroundStyle(Color.reasi.text)
            ForEach(brief.ideas) { idea in
                PlanIdeaRow(
                    idea: idea,
                    updateRole: { role in updateRole(role, ideaID: idea.id) },
                    remove: { removeIdea(idea.id) }
                )
            }
        }
    }

    private func interpretationSection(_ value: PlanInterpretation) -> some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            if let clarification = value.clarification, !clarification.isEmpty {
                VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                    Text(clarification)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    if !value.clarificationOptions.isEmpty {
                        ForEach(value.clarificationOptions, id: \.self) { option in
                            Button {
                                clarificationAnswer = option
                                ReasiHaptics.selection()
                            } label: {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    Image(systemName: clarificationAnswer == option ? "checkmark.circle.fill" : "circle")
                                }
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.text)
                                .padding(ReasiSpacing.s3)
                                .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md))
                            }
                            .buttonStyle(ReasiPressStyle())
                        }
                    }
                    TextField("Your answer", text: $clarificationAnswer)
                        .textFieldStyle(.plain)
                        .padding(ReasiSpacing.s3)
                        .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md))
                }
            }

            if let recommendation = value.recommendation {
                Text("One thing to complete it")
                    .font(ReasiTypography.headline)
                    .foregroundStyle(Color.reasi.text)
                recommendationButton(recommendation, recommended: true)
                if !value.swaps.isEmpty {
                    Text("Or swap it for")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                    ForEach(value.swaps.prefix(2)) { swap in
                        recommendationButton(swap, recommended: false)
                    }
                }
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private func recommendationButton(_ recommendation: PlanGapRecommendation, recommended: Bool) -> some View {
        Button {
            addIdea(
                title: recommendation.title,
                type: .dish,
                detail: recommendation.reason,
                courseHint: recommendation.courseRole
            )
            analytics.capture(.planGapRecommendationSelected, properties: [
                "recommended": .bool(recommended),
                "plan_kind": .string(brief.kind.rawValue)
            ])
        } label: {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                Image(systemName: recommended ? "sparkles" : "arrow.triangle.swap")
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title).font(ReasiTypography.bodyMedium)
                    Text(recommendation.reason).font(ReasiTypography.caption).foregroundStyle(Color.reasi.textMuted)
                }
                Spacer()
                Image(systemName: "plus.circle")
            }
            .foregroundStyle(Color.reasi.text)
            .padding(ReasiSpacing.s3)
            .background(Color.reasi.surfaceHigh, in: RoundedRectangle(cornerRadius: ReasiRadius.md))
        }
        .buttonStyle(ReasiPressStyle())
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack {
                Text("Budget target").font(ReasiTypography.headline).foregroundStyle(Color.reasi.text)
                Spacer()
                TextField("Optional", value: $brief.budgetTargetAud, format: .currency(code: "AUD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }
            if let target = brief.budgetTargetAud {
                Text(budgetMessage(target: target))
                    .font(ReasiTypography.caption)
                    .foregroundStyle(budgetKnownSubtotal > target ? Color.reasi.warning : Color.reasi.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if budgetKnownSubtotal > target {
                    Button("Use known subtotal as target") {
                        brief.budgetTargetAud = budgetKnownSubtotal
                        analytics.capture(.budgetRevisionRequested, properties: [
                            "plan_kind": .string(brief.kind.rawValue),
                            "priced_product_count": .int(budgetCoverage.pricedProductCount)
                        ])
                    }
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.text)
                    .buttonStyle(ReasiPressStyle())
                }
            } else {
                Text("A target guides choices. Reasi only compares it with prices we can source.")
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            Task { await reviewOrGenerate() }
        } label: {
            if isInterpreting {
                HStack { ProgressView().tint(Color.reasi.background); Text("Reviewing your plan") }
            } else {
                Label(interpretation == nil ? "Review plan" : "Create plan", systemImage: interpretation == nil ? "sparkles" : "arrow.right")
            }
        }
        .buttonStyle(ReasiPrimaryButtonStyle())
        .disabled(isInterpreting || (brief.briefText.isEmpty && brief.ideas.isEmpty))
    }

    private var budgetCoverage: PlanBudgetCoverage { PlanBudgetCoverage(ideas: brief.ideas) }
    private var budgetKnownSubtotal: Double { budgetCoverage.knownSubtotalAud }

    private func budgetMessage(target: Double) -> String {
        let priced = budgetCoverage.pricedProductCount
        let total = budgetCoverage.eligibleProductCount
        guard total > 0 else { return "No reliable product prices yet. The final list will show price coverage." }
        let subtotal = budgetKnownSubtotal.formatted(.currency(code: "AUD"))
        return "Known subtotal \(subtotal), based on \(priced) of \(total) priced products. This is guidance, not a checkout total."
    }

    private func addTypedInput() async {
        let value = newIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        errorMessage = nil
        if let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
            isResolving = true
            defer { isResolving = false }
            do {
                let resolved = try await supabase.resolveMealIdea(
                    method: "link",
                    storeId: appState.selectedStore.id,
                    url: value
                )
                addResolvedIdea(resolved)
                newIdea = ""
            } catch {
                errorMessage = supabase.userFacingMessage(for: error, fallback: "That link could not be read. Try a public recipe link or add a screenshot.")
            }
        } else {
            brief.briefText = [brief.briefText, value].filter { !$0.isEmpty }.joined(separator: ". ")
            if entryMethod == .build {
                addIdea(title: value, type: .dish)
            }
            newIdea = ""
        }
    }

    private func addIdea(
        title: String,
        type: IdeaType,
        detail: String? = nil,
        courseHint: String? = nil
    ) {
        brief.ideas.append(
            PlanIdea(type: type, title: title, detail: detail, courseHint: courseHint)
        )
        analytics.capture(.planIdeaAdded, properties: [
            "idea_type": .string(type.rawValue),
            "plan_kind": .string(brief.kind.rawValue),
            "entry_method": .string(brief.entryMethod.rawValue)
        ])
        ReasiHaptics.selection()
    }

    private func addProduct(_ candidate: ProductCandidate) {
        guard !brief.ideas.contains(where: { $0.product?.id == candidate.id }) else { return }
        let details = [
            candidate.brand,
            candidate.size,
            candidate.priceAud?.formatted(.currency(code: "AUD"))
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
        brief.ideas.append(PlanIdea(
            type: .product,
            title: candidate.displayName,
            detail: details.isEmpty ? nil : details,
            sourceURL: candidate.sourceUrl,
            product: candidate,
            productRole: .useInPlan
        ))
        analytics.capture(.planIdeaAdded, properties: ["idea_type": .string(IdeaType.product.rawValue)])
        ReasiHaptics.success()
    }

    private func addResolvedIdea(_ resolved: ResolvedMealIdea) {
        if let product = resolved.product {
            addProduct(product)
            return
        }
        brief.ideas.append(PlanIdea(
            type: .dish,
            title: resolved.title,
            detail: resolvedIdeaDetail(resolved),
            sourceURL: resolved.sourceURL
        ))
        analytics.capture(.planIdeaAdded, properties: ["idea_type": .string(IdeaType.dish.rawValue)])
    }

    private func updateRole(_ role: ProductRole, ideaID: String) {
        guard let index = brief.ideas.firstIndex(where: { $0.id == ideaID }) else { return }
        brief.ideas[index].productRole = role
        analytics.capture(.planProductRoleSelected, properties: ["role": .string(role.rawValue)])
        ReasiHaptics.selection()
    }

    private func resolvedIdeaDetail(_ resolved: ResolvedMealIdea) -> String? {
        var parts = [resolved.description].compactMap { $0 }
        if let recipe = resolved.recipe {
            let ingredients = recipe.ingredients.prefix(8).map(\.name).joined(separator: ", ")
            if !ingredients.isEmpty { parts.append("Ingredients: \(ingredients)") }
            if let totalTime = recipe.totalTimeMin { parts.append("About \(totalTime) minutes") }
        }
        let joined = parts.joined(separator: ". ")
        return joined.isEmpty ? nil : String(joined.prefix(800))
    }

    private func removeIdea(_ id: String) {
        brief.ideas.removeAll { $0.id == id }
        ReasiHaptics.selection()
    }

    private func pickPhoto(_ mode: BuilderPhotoMode) {
        photoMode = mode
        selectedPhoto = nil
        isPhotoPickerPresented = true
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false; selectedPhoto = nil }
        do {
            guard let originalData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: originalData),
                  let data = image.jpegData(compressionQuality: 0.84) else {
                throw ReasiServiceError.invalidResponse
            }
            switch photoMode {
            case .meal:
                let path = try await supabase.uploadUserImage(data, kind: .productPhoto)
                let resolved = try await supabase.resolveMealIdea(
                    method: "photo",
                    storeId: appState.selectedStore.id,
                    uploadPath: path
                )
                addResolvedIdea(resolved)
            case .product:
                let path = try await supabase.uploadUserImage(data, kind: .productPhoto)
                let result = try await supabase.resolveProduct(
                    input: ResolveProductInput(
                        method: "product_photo",
                        storeId: appState.selectedStore.id,
                        query: nil,
                        url: nil,
                        uploadPath: path
                    )
                )
                if let candidate = result.candidates.first { addProduct(candidate) }
                else { errorMessage = "No reliable product match was found. Try scanning its barcode." }
            case .handwrittenList:
                let path = try await supabase.uploadUserImage(data, kind: .shoppingListPhoto)
                let result = try await supabase.extractShoppingListPhoto(storeId: appState.selectedStore.id, uploadPath: path)
                for item in result.items {
                    if let candidate = item.productCandidate { addProduct(candidate) }
                    else { addIdea(title: item.extractedName, type: .listItem, detail: item.quantity) }
                }
            }
        } catch {
            errorMessage = supabase.userFacingMessage(for: error, fallback: "That photo could not be read. Try a clearer, well-lit image.")
        }
    }

    private func reviewOrGenerate() async {
        errorMessage = nil
        if interpretation == nil {
            isInterpreting = true
            defer { isInterpreting = false }
            do {
                let result = try await supabase.interpretPlanBrief(brief, storeId: appState.selectedStore.id)
                if let normalized = result.normalizedBrief {
                    brief = normalized.mergingClientMetadata(from: brief)
                }
                interpretation = result
                analytics.capture(.planBriefInterpreted, properties: [
                    "plan_kind": .string(brief.kind.rawValue),
                    "entry_method": .string(brief.entryMethod.rawValue),
                    "has_clarification": .bool(result.clarification?.isEmpty == false)
                ])
                if result.recommendation != nil {
                    analytics.capture(.planGapRecommendationViewed, properties: ["plan_kind": .string(brief.kind.rawValue)])
                }
                if let target = brief.budgetTargetAud, budgetKnownSubtotal > target {
                    analytics.capture(.budgetWarningViewed, properties: ["plan_kind": .string(brief.kind.rawValue)])
                }
                ReasiHaptics.success()
            } catch {
                errorMessage = supabase.userFacingMessage(for: error, fallback: "We couldn't review this plan yet. Your draft is safe.")
            }
            return
        }

        if !clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            brief.briefText += ". Clarification: \(clarificationAnswer)"
        }
        analytics.capture(.planConfirmed, properties: [
            "plan_kind": .string(brief.kind.rawValue),
            "entry_method": .string(brief.entryMethod.rawValue),
            "idea_count": .int(brief.ideas.count)
        ])
        coreLoop.startPlanGeneration(
            brief: brief,
            store: appState.selectedStore,
            supabase: supabase,
            analytics: analytics,
            appState: appState,
            network: network
        )
        dismiss()
    }
}

private enum BuilderPhotoMode {
    case meal
    case product
    case handwrittenList
}

private struct PlanIdeaRow: View {
    let idea: PlanIdea
    let updateRole: (ProductRole) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: ReasiSpacing.s3) {
            Image(systemName: idea.type == .product ? "shippingbox.fill" : (idea.type == .dish ? "fork.knife" : "checklist"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(idea.type == .product ? Color.reasi.warning : Color.reasi.textMuted)
                .frame(width: 36, height: 36)
                .background(Color.reasi.surfaceHigh, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                    .lineLimit(2)
                if idea.type == .product {
                    Menu(idea.productRole?.title ?? ProductRole.useInPlan.title) {
                        ForEach(ProductRole.allCases, id: \.self) { role in
                            Button(role.title) { updateRole(role) }
                        }
                    }
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.warning)
                } else if let detail = idea.detail, !detail.isEmpty {
                    Text(detail).font(ReasiTypography.caption).foregroundStyle(Color.reasi.muted).lineLimit(2)
                }
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.reasi.dim)
            }
            .accessibilityLabel("Remove \(idea.title)")
        }
        .padding(ReasiSpacing.s3)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                .stroke(idea.type == .product ? Color.reasi.warning.opacity(0.35) : Color.reasi.border, lineWidth: 1)
        }
    }
}
