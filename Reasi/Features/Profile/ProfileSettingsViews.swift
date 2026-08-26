import SwiftUI
import UIKit

enum ProfileSettingsDestination: String, Identifiable {
    case planning
    case store
    case shopping
    case reminders

    var id: String { rawValue }
}

struct PlanningPreferencesSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: OnboardingPreferences
    @State private var isSaving = false

    let onSave: (OnboardingPreferences) async -> Void

    init(
        preferences: OnboardingPreferences,
        onSave: @escaping (OnboardingPreferences) async -> Void
    ) {
        _draft = State(initialValue: preferences)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s8) {
                    settingsIntro(
                        "Shape your week",
                        detail: "These choices guide every new meal plan."
                    )
                    goalSection
                    householdSection
                    foodStyleSection
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s4)
                .padding(.bottom, 116)
            }
            .background(Color.reasi.background)
            .navigationTitle("Meal planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbarItem(dismiss: dismiss) }
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                settingsBottomBar {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: ReasiSpacing.s3) {
                            if isSaving {
                                ProgressView()
                                    .tint(Color.reasi.background)
                            }
                            Text(isSaving ? "Saving" : "Save preferences")
                        }
                    }
                    .buttonStyle(ReasiPrimaryButtonStyle())
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.72 : 1)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var goalSection: some View {
        settingsSection("Main goal") {
            VStack(spacing: ReasiSpacing.s2) {
                ForEach(OnboardingPurpose.allCases) { purpose in
                    Button {
                        draft.purpose = purpose
                        ReasiHaptics.selection()
                    } label: {
                        selectionRow(
                            title: purpose.title,
                            detail: purpose.summary,
                            symbol: purpose.symbol,
                            isSelected: draft.purpose == purpose
                        )
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }
        }
    }

    private var householdSection: some View {
        settingsSection("Cooking for") {
            VStack(spacing: ReasiSpacing.s2) {
                ForEach(HouseholdChoice.allCases) { household in
                    Button {
                        draft.household = household
                        ReasiHaptics.selection()
                    } label: {
                        selectionRow(
                            title: household.title,
                            detail: "Recipes and quantities for \(household.householdSize)",
                            symbol: household.householdSize == 1 ? "person" : "person.2",
                            isSelected: draft.household == household
                        )
                    }
                    .buttonStyle(ReasiPressStyle())
                }
            }
        }
    }

    private var foodStyleSection: some View {
        settingsSection("Food styles") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: ReasiSpacing.s2)],
                spacing: ReasiSpacing.s2
            ) {
                ForEach(FoodStyle.allCases) { style in
                    Button {
                        if draft.foodStyles.contains(style) {
                            draft.foodStyles.remove(style)
                        } else {
                            draft.foodStyles.insert(style)
                        }
                        ReasiHaptics.selection()
                    } label: {
                        HStack(spacing: ReasiSpacing.s2) {
                            Image(systemName: draft.foodStyles.contains(style) ? "checkmark" : styleSymbol(style))
                                .font(.system(size: 13, weight: .semibold))
                            Text(style.title)
                                .font(ReasiTypography.callout)
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)
                        }
                        .foregroundStyle(
                            draft.foodStyles.contains(style) ? Color.reasi.background : Color.reasi.text
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, ReasiSpacing.s3)
                        .background(
                            draft.foodStyles.contains(style) ? Color.reasi.text : Color.reasi.surface,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(
                                draft.foodStyles.contains(style) ? Color.clear : Color.reasi.borderStrong,
                                lineWidth: 1
                            )
                        }
                    }
                    .buttonStyle(ReasiPressStyle())
                    .accessibilityLabel(style.title)
                    .accessibilityValue(draft.foodStyles.contains(style) ? "Selected" : "Not selected")
                }
            }
        }
    }

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

struct StoreSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStore: StoreSummary

    let onSelect: (StoreSummary) -> Void

    init(selectedStore: StoreSummary, onSelect: @escaping (StoreSummary) -> Void) {
        _selectedStore = State(initialValue: selectedStore)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s6) {
                    settingsIntro(
                        "Choose your store",
                        detail: "Reasi will build future lists in that store's walking order."
                    )

                    VStack(spacing: ReasiSpacing.s2) {
                        ForEach(FixtureStores.launchStores) { store in
                            Button {
                                selectedStore = store
                                ReasiHaptics.selection()
                            } label: {
                                HStack(spacing: ReasiSpacing.s4) {
                                    Image(systemName: "storefront")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.reasi.textMuted)
                                        .frame(width: 42, height: 42)
                                        .background(Color.reasi.surfaceHigh, in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.shortName)
                                            .font(ReasiTypography.bodyMedium)
                                            .foregroundStyle(Color.reasi.text)
                                        Text(store.retailerDisplayName)
                                            .font(ReasiTypography.caption)
                                            .foregroundStyle(Color.reasi.muted)
                                    }

                                    Spacer()

                                    Image(systemName: selectedStore.id == store.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(
                                            selectedStore.id == store.id ? Color.reasi.success : Color.reasi.dim
                                        )
                                }
                                .padding(ReasiSpacing.s4)
                                .frame(minHeight: 72)
                                .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
                                        .stroke(
                                            selectedStore.id == store.id ? Color.reasi.borderStrong : Color.reasi.border,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(ReasiPressStyle())
                            .accessibilityLabel(store.name)
                            .accessibilityValue(selectedStore.id == store.id ? "Selected" : "Not selected")
                        }
                    }
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s4)
                .padding(.bottom, 116)
            }
            .background(Color.reasi.background)
            .navigationTitle("Preferred store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbarItem(dismiss: dismiss) }
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                settingsBottomBar {
                    Button {
                        onSelect(selectedStore)
                        dismiss()
                    } label: {
                        Text("Use \(selectedStore.shortName)")
                    }
                    .buttonStyle(ReasiPrimaryButtonStyle())
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ShoppingPreferencesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(AnalyticsService.self) private var analytics

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
                    settingsIntro(
                        "Shopping mode",
                        detail: "Keep the list focused while you move through the store."
                    )

                    settingsSection("List") {
                        VStack(spacing: 1) {
                            settingsToggleRow(
                                title: "Hide bought items",
                                detail: "Checked items collapse into one quiet summary.",
                                symbol: "checkmark.circle",
                                isOn: Binding(
                                    get: { userSettings.hideCompletedItems },
                                    set: { enabled in setHideCompletedItems(enabled) }
                                )
                            )
                            settingsToggleRow(
                                title: "Keep screen awake",
                                detail: "Only while your shopping list is open.",
                                symbol: "sun.max",
                                isOn: Binding(
                                    get: { userSettings.keepScreenAwake },
                                    set: { enabled in setKeepScreenAwake(enabled) }
                                )
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                                .stroke(Color.reasi.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s4)
                .padding(.bottom, 116)
            }
            .background(Color.reasi.background)
            .navigationTitle("List behavior")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbarItem(dismiss: dismiss) }
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                settingsBottomBar {
                    Button("Done") { dismiss() }
                        .buttonStyle(ReasiPrimaryButtonStyle())
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func setHideCompletedItems(_ enabled: Bool) {
        userSettings.setHideCompletedItems(enabled)
        ReasiHaptics.selection()
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("hide_completed_items"),
            "enabled": .bool(enabled)
        ])
    }

    private func setKeepScreenAwake(_ enabled: Bool) {
        userSettings.setKeepScreenAwake(enabled)
        ReasiHaptics.selection()
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("keep_screen_awake"),
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ReasiSpacing.s7) {
                    settingsIntro(
                        "Make planning automatic",
                        detail: "Choose one calm moment each week to plan before the rush."
                    )

                    settingsSection("Reminder") {
                        VStack(spacing: 1) {
                            settingsToggleRow(
                                title: "Weekly reminder",
                                detail: userSettings.planningReminderEnabled ? userSettings.reminderSummary : "No reminder scheduled",
                                symbol: "bell",
                                isOn: Binding(
                                    get: { userSettings.planningReminderEnabled },
                                    set: { enabled in updateReminderEnabled(enabled) }
                                )
                            )

                            if userSettings.planningReminderEnabled {
                                settingsControlRow(title: "Day", symbol: "calendar") {
                                    Picker(
                                        "Day",
                                        selection: Binding(
                                            get: { userSettings.planningReminderDay },
                                            set: { day in updateReminderDay(day) }
                                        )
                                    ) {
                                        ForEach(WeeklyPlanningDay.allCases) { day in
                                            Text(day.title).tag(day)
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(Color.reasi.textMuted)
                                }

                                settingsControlRow(title: "Time", symbol: "clock") {
                                    Picker(
                                        "Time",
                                        selection: Binding(
                                            get: { userSettings.planningReminderMinuteOfDay },
                                            set: { minute in updateReminderTime(minute) }
                                        )
                                    ) {
                                        ForEach(reminderTimeOptions, id: \.self) { minuteOfDay in
                                            Text(reminderTimeLabel(minuteOfDay)).tag(minuteOfDay)
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(Color.reasi.text)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                                .stroke(Color.reasi.border, lineWidth: 1)
                        }
                    }

                    permissionStatus
                }
                .padding(.horizontal, ReasiSpacing.s5)
                .padding(.top, ReasiSpacing.s4)
                .padding(.bottom, 116)
            }
            .background(Color.reasi.background)
            .navigationTitle("Weekly reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbarItem(dismiss: dismiss) }
            .toolbarBackground(Color.reasi.background, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                settingsBottomBar {
                    Button("Done") { dismiss() }
                        .buttonStyle(ReasiPrimaryButtonStyle())
                }
            }
            .task {
                await userSettings.refreshNotificationPermission()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var permissionStatus: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
            HStack(spacing: ReasiSpacing.s3) {
                Image(systemName: userSettings.notificationPermission == .denied ? "bell.slash" : "checkmark.shield")
                    .foregroundStyle(
                        userSettings.notificationPermission == .denied ? Color.reasi.warning : Color.reasi.textMuted
                    )
                Text("Notification access")
                    .font(ReasiTypography.callout)
                    .foregroundStyle(Color.reasi.textMuted)
                Spacer()
                if isUpdating {
                    ProgressView()
                        .tint(Color.reasi.text)
                } else {
                    Text(userSettings.notificationPermission.label)
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                }
            }

            if let reminderMessage = userSettings.reminderMessage {
                Text(reminderMessage)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(
                        userSettings.notificationPermission == .denied ? Color.reasi.warning : Color.reasi.muted
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if userSettings.notificationPermission == .denied,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    Label("Open iPhone Settings", systemImage: "arrow.up.right")
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.text)
                        .padding(.vertical, ReasiSpacing.s2)
                }
            }
        }
        .padding(ReasiSpacing.s4)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
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

    private var reminderTimeOptions: [Int] {
        Array(stride(from: 0, to: 24 * 60, by: 30))
    }

    private func updateReminderTime(_ minuteOfDay: Int) {
        userSettings.setPlanningReminderTime(minutesFromMidnight: minuteOfDay)
        analytics.capture(.settingsUpdated, properties: [
            "setting": .string("reminder_time")
        ])
    }

    private func reminderTimeLabel(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

private func settingsIntro(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: ReasiSpacing.s2) {
        Text(title)
            .font(ReasiTypography.title2)
            .foregroundStyle(Color.reasi.text)
        Text(detail)
            .font(ReasiTypography.callout)
            .foregroundStyle(Color.reasi.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: ReasiSpacing.s3) {
        Text(title.uppercased())
            .font(ReasiTypography.caption)
            .foregroundStyle(Color.reasi.muted)
            .padding(.leading, ReasiSpacing.s1)
        content()
    }
}

private func selectionRow(
    title: String,
    detail: String,
    symbol: String,
    isSelected: Bool
) -> some View {
    HStack(spacing: ReasiSpacing.s4) {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.reasi.textMuted)
            .frame(width: 40, height: 40)
            .background(Color.reasi.surfaceHigh, in: Circle())

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ReasiTypography.bodyMedium)
                .foregroundStyle(Color.reasi.text)
            Text(detail)
                .font(ReasiTypography.caption)
                .foregroundStyle(Color.reasi.muted)
                .lineLimit(2)
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(isSelected ? Color.reasi.success : Color.reasi.dim)
    }
    .padding(ReasiSpacing.s4)
    .frame(minHeight: 72)
    .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: ReasiRadius.lg, style: .continuous)
            .stroke(isSelected ? Color.reasi.borderStrong : Color.reasi.border, lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
}

private func settingsToggleRow(
    title: String,
    detail: String,
    symbol: String,
    isOn: Binding<Bool>
) -> some View {
    Toggle(isOn: isOn) {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.text)
                Text(detail)
                    .font(ReasiTypography.caption)
                    .foregroundStyle(Color.reasi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.reasi.muted)
        }
    }
    .tint(Color.reasi.text)
    .padding(ReasiSpacing.s4)
    .frame(minHeight: 68)
    .background(Color.reasi.surface)
}

private func settingsControlRow<Control: View>(
    title: String,
    symbol: String,
    @ViewBuilder control: () -> Control
) -> some View {
    HStack(spacing: ReasiSpacing.s4) {
        Image(systemName: symbol)
            .frame(width: 22)
            .foregroundStyle(Color.reasi.muted)
        Text(title)
            .font(ReasiTypography.bodyMedium)
            .foregroundStyle(Color.reasi.text)
        Spacer()
        control()
    }
    .padding(ReasiSpacing.s4)
    .frame(minHeight: 58)
    .background(Color.reasi.surface)
}

private func settingsBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.top, ReasiSpacing.s3)
        .padding(.bottom, ReasiSpacing.s2)
        .background(.ultraThinMaterial)
}

@ToolbarContentBuilder
private func closeToolbarItem(dismiss: DismissAction) -> some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.reasi.text)
                .frame(width: 34, height: 34)
                .background(Color.reasi.surfaceHigh, in: Circle())
        }
        .accessibilityLabel("Close")
    }
}

private func styleSymbol(_ style: FoodStyle) -> String {
    switch style {
    case .vietnamese, .chinese, .mediterranean: "globe.asia.australia"
    case .quickDinners: "clock"
    case .vegetarian: "leaf"
    case .highProtein: "bolt"
    case .batchCook: "square.stack.3d.up"
    }
}

#Preview("Plan settings") {
    PlanningPreferencesSettingsView(preferences: .empty) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Shopping settings") {
    ShoppingPreferencesSettingsView()
        .environment(UserSettingsStore())
        .environment(AnalyticsService())
        .preferredColorScheme(.dark)
}
