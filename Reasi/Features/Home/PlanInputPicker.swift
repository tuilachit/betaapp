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
