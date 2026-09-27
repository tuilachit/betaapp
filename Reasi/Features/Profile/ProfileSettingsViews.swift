import SwiftUI
import UIKit

enum ProfileSettingsDestination: String, Identifiable {
    case planning
    case store
    case spending
    case shopping
    case reminders
    case signIn

    var id: String { rawValue }
}

struct PlanningPreferencesSettingsView: View {
    @State private var draft: OnboardingPreferences
    @State private var isSaving = false

    private let original: OnboardingPreferences
    let onSave: (OnboardingPreferences) async -> Void

    init(preferences: OnboardingPreferences, onSave: @escaping (OnboardingPreferences) async -> Void) {
        original = preferences
        _draft = State(initialValue: preferences)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Household") {
                    Picker("Cooking for", selection: $draft.household) {
                        Text("Not set").tag(HouseholdChoice?.none)
                        ForEach(HouseholdChoice.allCases) { household in
                            Text(household.title).tag(Optional(household))
                        }
                    }
                    .accessibilityIdentifier("settings-household")
                }
                .listRowBackground(Color.reasi.surface)

                Section {
                    ForEach(FoodStyle.allCases) { style in
                        Button {
                            if draft.foodStyles.contains(style) {
                                draft.foodStyles.remove(style)
                            } else {
                                draft.foodStyles.insert(style)
                            }
                            ReasiHaptics.selection()
                        } label: {
                            settingsSelectionRow(style.title, selected: draft.foodStyles.contains(style))
                        }
                    }
                } header: {
                    Text("Food styles")
                } footer: {
                    Text("Choose as many as you like.")
                }
                .listRowBackground(Color.reasi.surface)

                Section {
                    ForEach(OnboardingPurpose.allCases) { purpose in
                        let rank = draft.selectedPurposes.firstIndex(of: purpose).map { $0 + 1 }
                        Button {
                            draft.togglePurpose(purpose)
                            ReasiHaptics.selection()
                        } label: {
                            settingsSelectionRow(purpose.title, selected: rank != nil, rank: rank)
                        }
                        .disabled(rank == nil && draft.selectedPurposes.count == OnboardingPreferences.maximumPurposeSelections)
                    }
                } header: {
                    Text("Priorities")
                } footer: {
                    Text("Choose up to 3, most important first. Deselect a choice to change its order.")
                }
                .listRowBackground(Color.reasi.surface)
            }
            .settingsFormStyle("Meal preferences")
            .modifier(SettingsEditor(hasChanges: draft != original, isSaving: isSaving) { save() })
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await onSave(draft)
            isSaving = false
            dismiss()
        }
    }
}

struct SpendingPreferencesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var budgetFocused: Bool
    @State private var draft: OnboardingPreferences
    @State private var budgetText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let original: OnboardingPreferences
    private let originalBudgetText: String
    let onSave: (OnboardingPreferences) async -> Void

    init(preferences: OnboardingPreferences, onSave: @escaping (OnboardingPreferences) async -> Void) {
        original = preferences
        let text = preferences.weeklyGroceryBudgetAud.map {
            $0.formatted(.number.locale(Locale(identifier: "en_AU")).grouping(.never).precision(.fractionLength(0...2)))
        } ?? ""
        originalBudgetText = text
        _draft = State(initialValue: preferences)
        _budgetText = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: ReasiSpacing.s3) {
                        Text("A$")
                            .foregroundStyle(Color.reasi.muted)
                        TextField("No target", text: $budgetText)
                            .keyboardType(.decimalPad)
                            .focused($budgetFocused)
                            .accessibilityLabel("Weekly budget")
                            .accessibilityIdentifier("settings-weekly-budget")
                    }
                    .padding(.vertical, ReasiSpacing.s2)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(ReasiTypography.callout)
                            .foregroundStyle(Color.reasi.danger)
                    }
                } header: {
                    Text("Weekly budget")
                } footer: {
                    Text("Leave blank for no target.")
                }
                .listRowBackground(Color.reasi.surface)

                Section {
                    ForEach(SpendingCoachTone.allCases) { tone in
                        Button {
                            draft.spendingCoachTone = tone
                            ReasiHaptics.selection()
                        } label: {
                            settingsSelectionRow(tone.title, selected: draft.spendingCoachTone == tone)
                        }
                    }
                } header: {
                    Text("Coaching tone")
                } footer: {
                    Text(draft.spendingCoachTone.detail)
                }
                .listRowBackground(Color.reasi.surface)
            }
            .settingsFormStyle("Budget & coaching")
            .modifier(SettingsEditor(hasChanges: hasChanges, isSaving: isSaving) { save() })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { budgetFocused = false }
                }
            }
        }
    }

    private var hasChanges: Bool {
        budgetText != originalBudgetText || draft.spendingCoachTone != original.spendingCoachTone
    }

    private func save() {
        guard !isSaving else { return }
        let normalized = budgetText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        if normalized.isEmpty {
            draft.weeklyGroceryBudgetAud = nil
        } else if let value = Double(normalized), value > 0, value <= 10_000 {
            draft.weeklyGroceryBudgetAud = value
        } else {
            errorMessage = "Enter an amount above zero, up to A$10,000."
            return
        }
        budgetFocused = false
        isSaving = true
        errorMessage = nil
        Task {
            await onSave(draft)
            isSaving = false
            dismiss()
        }
    }
}

struct StoreSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStore: StoreSummary
    private let originalStore: StoreSummary
    let onSelect: (StoreSummary) -> Void

    init(selectedStore: StoreSummary, onSelect: @escaping (StoreSummary) -> Void) {
        originalStore = selectedStore
        _selectedStore = State(initialValue: selectedStore)
        self.onSelect = onSelect
    }

    private var retailers: [String] {
        Array(Set(FixtureStores.launchStores.map(\.retailerDisplayName))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(retailers, id: \.self) { retailer in
                    Section(retailer) {
                        ForEach(FixtureStores.launchStores.filter { $0.retailerDisplayName == retailer }) { store in
                            Button {
                                selectedStore = store
                                ReasiHaptics.selection()
                            } label: {
                                settingsSelectionRow(store.shortName, selected: selectedStore.id == store.id)
                            }
                            .accessibilityLabel(store.name)
                        }
                    }
                    .listRowBackground(Color.reasi.surface)
                }
            }
            .settingsFormStyle("Preferred store")
            .modifier(SettingsEditor(hasChanges: selectedStore.id != originalStore.id, isSaving: false) {
                onSelect(selectedStore)
                dismiss()
            })
        }
    }
}

struct ShoppingPreferencesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(AnalyticsService.self) private var analytics

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hide bought items", isOn: Binding(
                        get: { userSettings.hideCompletedItems },
                        set: { enabled in
                            userSettings.setHideCompletedItems(enabled)
                            capture("hide_completed_items", enabled: enabled)
                        }
                    ))
                    .accessibilityIdentifier("settings-hide-bought")
                } footer: {
                    Text("Bought items stay on your list, tucked out of the way.")
                }
                .listRowBackground(Color.reasi.surface)

                Section {
                    Toggle("Keep screen awake", isOn: Binding(
                        get: { userSettings.keepScreenAwake },
                        set: { enabled in
                            userSettings.setKeepScreenAwake(enabled)
                            capture("keep_screen_awake", enabled: enabled)
                        }
                    ))
                } footer: {
                    Text("Only while your shopping list is open.")
                }
                .listRowBackground(Color.reasi.surface)
            }
            .settingsFormStyle("List behavior")
            .tint(Color.reasi.success)
            .toolbar { settingsDoneButton(dismiss: dismiss) }
        }
    }

    private func capture(_ setting: String, enabled: Bool) {
        ReasiHaptics.selection()
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string(setting),
            "enabled": .bool(enabled)
        ])
    }
}

struct PlanningReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(AnalyticsService.self) private var analytics
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Weekly reminder", isOn: Binding(
                        get: { userSettings.planningReminderEnabled },
                        set: { enabled in updateReminderEnabled(enabled) }
                    ))
                    .tint(Color.reasi.success)
                    .disabled(isUpdating)
                    if isUpdating {
                        ProgressView("Updating reminder")
                    }
                    if userSettings.planningReminderEnabled {
                        Picker("Day", selection: Binding(
                            get: { userSettings.planningReminderDay },
                            set: { day in updateReminderDay(day) }
                        )) {
                            ForEach(WeeklyPlanningDay.allCases) { day in
                                Text(day.title).tag(day)
                            }
                        }
                        Picker("Time", selection: Binding(
                            get: { userSettings.planningReminderMinuteOfDay },
                            set: { minute in updateReminderTime(minute) }
                        )) {
                            ForEach(Array(stride(from: 0, to: 24 * 60, by: 30)), id: \.self) { minute in
                                Text(reminderTimeLabel(minute)).tag(minute)
                            }
                        }
                    }
                }
                .listRowBackground(Color.reasi.surface)

                if userSettings.notificationPermission == .denied || userSettings.reminderMessage != nil {
                    Section {
                        if let message = userSettings.reminderMessage {
                            Text(message)
                                .font(ReasiTypography.callout)
                                .foregroundStyle(Color.reasi.textMuted)
                        }
                        if userSettings.notificationPermission == .denied,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open iPhone Settings", destination: url)
                        }
                    } header: {
                        Text("Notification access")
                    }
                    .listRowBackground(Color.reasi.surface)
                }
            }
            .settingsFormStyle("Weekly reminder")
            .toolbar { settingsDoneButton(dismiss: dismiss) }
            .task { await userSettings.refreshNotificationPermission() }
        }
    }

    private func updateReminderEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        Task {
            await userSettings.setPlanningReminderEnabled(enabled)
            analytics.capture(.settingsUpdated, properties: [
                "setting": .string("weekly_reminder"),
                "enabled": .bool(userSettings.planningReminderEnabled)
            ])
            if userSettings.planningReminderEnabled { ReasiHaptics.success() }
            isUpdating = false
        }
    }

    private func updateReminderDay(_ day: WeeklyPlanningDay) {
        userSettings.setPlanningReminderDay(day)
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("reminder_day"),
            "weekday": .int(day.rawValue)
        ])
        ReasiHaptics.selection()
    }

    private func updateReminderTime(_ minute: Int) {
        userSettings.setPlanningReminderTime(minutesFromMidnight: minute)
        analytics.capture(.settingsUpdated, properties: ["setting": .string("reminder_time")])
    }

    private func reminderTimeLabel(_ minute: Int) -> String {
        let hour = minute / 60
        return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute % 60, hour < 12 ? "AM" : "PM")
    }
}

private extension View {
    func settingsFormStyle(_ title: String) -> some View {
        self
            .font(ReasiTypography.body)
            .foregroundStyle(Color.reasi.text)
            .scrollContentBackground(.hidden)
            .background(Color.reasi.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .tint(Color.reasi.text)
    }
}

private struct SettingsEditor: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    let hasChanges: Bool
    let isSaving: Bool
    let save: () -> Void

    func body(content: Content) -> some View {
        content
            .disabled(isSaving)
            .interactiveDismissDisabled(hasChanges || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        if hasChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Saving")
                    } else if hasChanges {
                        Button("Save", action: save)
                            .font(ReasiTypography.headline)
                            .accessibilityIdentifier("settings-save")
                    }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
    }
}

private func settingsSelectionRow(_ title: String, selected: Bool, rank: Int? = nil) -> some View {
    HStack(spacing: ReasiSpacing.s3) {
        Text(title)
            .font(ReasiTypography.body)
            .foregroundStyle(Color.reasi.text)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: ReasiSpacing.s2)
        if let rank {
            Text("\(rank)")
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.background)
                .frame(width: 24, height: 24)
                .background(Color.reasi.text, in: Circle())
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 24)
                .opacity(selected ? 1 : 0)
        }
    }
    .padding(.vertical, ReasiSpacing.s2)
    .frame(minHeight: 36)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(rank.map { "Priority \($0)" } ?? (selected ? "Selected" : "Not selected"))
    .accessibilityAddTraits(selected ? .isSelected : [])
}

@ToolbarContentBuilder
private func settingsDoneButton(dismiss: DismissAction) -> some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
            .font(ReasiTypography.headline)
            .tint(Color.reasi.text)
    }
}

#Preview("Meal preferences") {
    PlanningPreferencesSettingsView(preferences: .empty) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("List behavior") {
    ShoppingPreferencesSettingsView()
        .environment(UserSettingsStore())
        .environment(AnalyticsService())
        .preferredColorScheme(.dark)
}
