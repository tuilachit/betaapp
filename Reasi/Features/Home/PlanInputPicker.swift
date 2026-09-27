import SwiftUI

enum PlanInputAction: String, CaseIterable, Identifiable {
    case mealPhoto, findProduct, productPhoto, listPhoto

    var id: Self { self }

    var title: String {
        switch self {
        case .mealPhoto: "Meal photo"
        case .findProduct: "Find product"
        case .productPhoto: "Product photo"
        case .listPhoto: "List photo"
        }
    }

    var symbol: String {
        switch self {
        case .mealPhoto: "fork.knife.circle"
        case .findProduct: "magnifyingglass"
        case .productPhoto: "shippingbox"
        case .listPhoto: "text.viewfinder"
        }
    }

    var hint: String {
        switch self {
        case .mealPhoto: "Choose a meal photo or recipe screenshot from your library"
        case .findProduct: "Search groceries, paste a product link, or scan a barcode"
        case .productPhoto: "Choose a photo of an ingredient or package from your library"
        case .listPhoto: "Choose a photographed shopping list from your library"
        }
    }
}

struct PlanInputPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSelecting = false

    let onSelect: (PlanInputAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: ReasiSpacing.s4),
                                   count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: ReasiSpacing.s5
                ) {
                    ForEach(PlanInputAction.allCases) { action in
                        Button {
                            guard !isSelecting else { return }
                            isSelecting = true
                            ReasiHaptics.selection()
                            onSelect(action)
                            dismiss()
                        } label: {
                            optionLabel(action)
                                .frame(maxWidth: .infinity, minHeight: 116)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(action.title)
                        .accessibilityHint(action.hint)
                        .disabled(isSelecting)
                    }
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s5)
                .padding(.bottom, ReasiSpacing.s6)
            }
            .background(Color.reasi.surface)
            .navigationTitle("Add to your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close add options", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .foregroundStyle(Color.reasi.text)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(420), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.reasi.surface)
        .presentationCornerRadius(ReasiRadius.xl)
        .presentationContentInteraction(.scrolls)
    }

    @ViewBuilder
    private func optionLabel(_ action: PlanInputAction) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: ReasiSpacing.s4) {
                optionIcon(action)
                optionTitle(action)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: ReasiSpacing.s3) {
                optionIcon(action)
                optionTitle(action)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func optionIcon(_ action: PlanInputAction) -> some View {
        Image(systemName: action.symbol)
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(action == .mealPhoto ? Color.reasi.success : Color.reasi.text)
            .frame(width: 80, height: 80)
            .background(action == .mealPhoto ? Color.reasi.planHighlight : Color.reasi.surfaceHigh, in: Circle())
            .accessibilityHidden(true)
    }

    private func optionTitle(_ action: PlanInputAction) -> some View {
        Text(action.title)
            .font(.callout.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PlanPhotoReview: Identifiable {
    let id = UUID()
    var ideas: [PlanIdea]
    let singleSelection: Bool
    var selectedIDs: Set<String>

    init(ideas: [PlanIdea], singleSelection: Bool = false) {
        self.ideas = ideas
        self.singleSelection = singleSelection
        let clear = ideas.filter { $0.confidence != .low }.map(\.id)
        selectedIDs = Set(singleSelection ? Array(clear.prefix(1)) : clear)
    }

    var confirmedIdeas: [PlanIdea] {
        ideas.filter { selectedIDs.contains($0.id) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else if singleSelection { selectedIDs = [id] }
        else { selectedIDs.insert(id) }
    }

    #if DEBUG
    static var uiTestFixture: PlanPhotoReview {
        PlanPhotoReview(ideas: [
            PlanIdea.photographedListItem(ListExtractionCandidate(extractedName: "Milk", quantity: "2 L", group: .needsReview, confidence: .high, confidenceReason: "Check the amount against your photo.", productCandidate: nil), uploadPath: "fixture/list.jpg"),
            PlanIdea.photographedListItem(ListExtractionCandidate(extractedName: "Chicken thing", quantity: nil, group: .uncertain, confidence: .low, confidenceReason: "The handwriting is unclear.", productCandidate: nil), uploadPath: "fixture/list.jpg")
        ])
    }
    #endif
}

struct PlanPhotoReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var review: PlanPhotoReview
    @State private var didAdd = false
    let onConfirm: ([PlanIdea]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ReasiSpacing.s5) {
                    ForEach(review.ideas.indices, id: \.self) { index in
                        reviewRow(index)
                        Divider()
                    }
                }
                .padding(ReasiSpacing.s5)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.reasi.background)
            .navigationTitle("Check your photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard !didAdd else { return }
                    didAdd = true
                    onConfirm(review.confirmedIdeas)
                    dismiss()
                } label: {
                    Text("Add \(review.confirmedIdeas.count)")
                        .font(ReasiTypography.bodyMedium)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.reasi.text)
                .foregroundStyle(Color.reasi.background)
                .disabled(review.confirmedIdeas.isEmpty || didAdd)
                .accessibilityIdentifier("photo-review-add")
                .padding(ReasiSpacing.s5)
                .background(Color.reasi.background)
            }
        }
        .foregroundStyle(Color.reasi.text)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func reviewRow(_ index: Int) -> some View {
        let idea = review.ideas[index]
        return HStack(alignment: .top, spacing: ReasiSpacing.s3) {
            Button { review.toggle(idea.id) } label: {
                Image(systemName: review.selectedIDs.contains(idea.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include \(idea.title)")
            .accessibilityValue(review.selectedIDs.contains(idea.id) ? "Selected" : "Not selected")
            .accessibilityIdentifier("photo-review-select-\(index)")

            VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
                TextField("Item name", text: Binding(get: { review.ideas[index].title }, set: { value in
                    review.ideas[index].title = value
                    review.ideas[index].product = nil
                    review.ideas[index].productReference = nil
                }), axis: .vertical)
                .font(ReasiTypography.bodyMedium)
                .accessibilityIdentifier("photo-review-name-\(index)")

                if idea.type != .dish {
                    TextField("Quantity", text: Binding(get: { review.ideas[index].quantity ?? "" }, set: {
                        review.ideas[index].quantity = $0.isEmpty ? nil : $0
                    }))
                    .font(ReasiTypography.callout)
                    .accessibilityIdentifier("photo-review-quantity-\(index)")

                    Picker("Use", selection: Binding(get: { review.ideas[index].productRole ?? .addToList }, set: { role in
                        review.ideas[index].productRole = role
                        review.ideas[index].type = role == .addToList && idea.product == nil ? .listItem : .product
                    })) {
                        ForEach(ProductRole.allCases, id: \.self) { role in
                            Text(role == .addToList ? "Just buy" : role.title).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.reasi.text)
                }

                if idea.confidence == .low {
                    Label("Check this item", systemImage: "exclamationmark.circle")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.warning)
                } else if idea.type == .dish && idea.recipe == nil {
                    Text("Meal inspiration")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.textMuted)
                }

                DisclosureGroup(idea.recipe == nil ? "Details" : "Recipe") {
                    VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                        if let reason = idea.confidenceReason { Text(reason.reasiUserFacingCopy) }
                        if let recipe = idea.recipe {
                            ForEach(recipe.ingredients) { ingredient in
                                Text([ingredient.quantity, ingredient.name].filter { !$0.isEmpty }.joined(separator: " "))
                            }
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)")
                            }
                        }
                    }
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.textMuted)
                }
                .font(ReasiTypography.caption)
                .tint(Color.reasi.textMuted)
            }
            .padding(.top, ReasiSpacing.s2)
        }
    }
}
