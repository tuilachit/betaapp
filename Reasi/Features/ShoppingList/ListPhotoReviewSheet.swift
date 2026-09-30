import SwiftUI

struct ListPhotoDraft: Identifiable {
    let id = UUID()
    let items: [ListPhotoItemDraft]
    let shoppingListID: String?

    init(result: ListExtractionResult, shoppingListID: String? = nil) {
        items = result.items.map(ListPhotoItemDraft.init)
        self.shoppingListID = shoppingListID
    }
}

struct ListPhotoItemDraft: Identifiable {
    let id = UUID().uuidString
    var name: String
    var quantity: String
    var isSelected = true
    let needsCheck: Bool

    init(_ item: ListExtractionCandidate) {
        name = item.extractedName
        quantity = item.quantity ?? ""
        needsCheck = item.confidence == .low || item.group == .uncertain
    }

    var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanedQuantity: String { quantity.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canAdd: Bool { isSelected && !cleanedName.isEmpty }

    var candidate: ProductCandidate {
        ProductCandidate(
            observationId: nil, name: cleanedName, brand: nil, size: nil,
            priceAud: nil, unitPriceAud: nil, unitQuantity: nil, unitMeasure: nil,
            comparablePrice: nil, imageUrl: nil, productUrl: nil,
            sourceName: "List photo", sourceUrl: nil, capturedAt: nil,
            freshnessLabel: "Not priced", confidence: .low,
            confidenceReason: "Added from your list photo.",
            uncertaintyText: "Price and location have not been matched."
        )
    }
}

struct ListPhotoReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ListPhotoItemDraft]
    @State private var addedIDs: Set<String> = []
    @State private var isAdding = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    let onAdd: (ListPhotoItemDraft) async -> Bool

    private enum Field: Hashable {
        case name(String), quantity(String)
    }

    init(draft: ListPhotoDraft, onAdd: @escaping (ListPhotoItemDraft) async -> Bool) {
        _items = State(initialValue: draft.items)
        self.onAdd = onAdd
    }

    private var pendingItems: [ListPhotoItemDraft] {
        items.filter { $0.canAdd && !addedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                            Button {
                                item.isSelected.toggle()
                            } label: {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(item.isSelected ? Color.reasi.text : Color.reasi.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Include \(item.name)")
                            .accessibilityValue(item.isSelected ? "Selected" : "Not selected")

                            VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
                                TextField("Item", text: $item.name, axis: .vertical)
                                    .font(ReasiTypography.bodyMedium)
                                    .accessibilityLabel("Item name")
                                    .focused($focusedField, equals: .name(item.id))
                                TextField("Quantity", text: $item.quantity)
                                    .font(ReasiTypography.callout)
                                    .foregroundStyle(Color.reasi.textMuted)
                                    .accessibilityLabel("Quantity for \(item.name)")
                                    .focused($focusedField, equals: .quantity(item.id))
                                if addedIDs.contains(item.id) {
                                    Label("Added", systemImage: "checkmark")
                                        .font(ReasiTypography.caption)
                                        .foregroundStyle(Color.reasi.success)
                                } else if item.needsCheck {
                                    Text("Check spelling")
                                        .font(ReasiTypography.caption)
                                        .foregroundStyle(Color.reasi.textMuted)
                                }
                            }
                            .padding(.vertical, ReasiSpacing.s2)
                        }
                        .disabled(isAdding || addedIDs.contains(item.id))
                        .listRowBackground(Color.reasi.background)
                    }
                } header: {
                    Text("\(items.count) items found")
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(Color.reasi.text)
            .background(Color.reasi.background)
            .navigationTitle("Your list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: ReasiSpacing.s3) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(ReasiTypography.caption)
                            .foregroundStyle(Color.reasi.warning)
                    }
                    Button {
                        guard !isAdding else { return }
                        focusedField = nil
                        isAdding = true
                        errorMessage = nil
                        let selected = pendingItems
                        Task { @MainActor in
                            for item in selected {
                                guard await onAdd(item) else {
                                    errorMessage = "Some items weren't added. Your edits are still here; try again."
                                    isAdding = false
                                    return
                                }
                                addedIDs.insert(item.id)
                            }
                            isAdding = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: ReasiSpacing.s2) {
                            if isAdding { ProgressView().tint(Color.reasi.background) }
                            Text(isAdding ? "Adding items" : "Add \(pendingItems.count) \(pendingItems.count == 1 ? "item" : "items")")
                        }
                    }
                    .buttonStyle(ReasiPrimaryButtonStyle())
                    .disabled(isAdding || pendingItems.isEmpty)
                    .accessibilityIdentifier("list-photo-add-items")
                }
                .padding(ReasiSpacing.s4)
                .background(Color.reasi.background)
            }
        }
        .interactiveDismissDisabled(isAdding)
    }
}

#if DEBUG
extension ListPhotoReviewSheet {
    static var fixtureExtraction: ListExtractionResult {
        let items = [
            ListExtractionCandidate(extractedName: "Oat milk", quantity: "2 L", group: .needsReview,
                                    confidence: .high, confidenceReason: "", productCandidate: nil),
            ListExtractionCandidate(extractedName: "chicken thing", quantity: nil, group: .uncertain,
                                    confidence: .low, confidenceReason: "Partly readable", productCandidate: nil),
            ListExtractionCandidate(extractedName: "Coriander", quantity: "1 bunch", group: .needsReview,
                                    confidence: .high, confidenceReason: "", productCandidate: nil),
        ]
        return ListExtractionResult(batchId: "ui-photo-review", matched: [], needsReview: Array(items.prefix(1)),
                                    uncertain: [items[1]], items: items)
    }
}
#endif
