import Foundation
import Observation
import UserNotifications

enum ReasiSettingKey {
    static let hapticsEnabled = "reasi.settings.hapticsEnabled"
    static let hideCompletedItems = "reasi.settings.hideCompletedItems"
    static let keepScreenAwake = "reasi.settings.keepScreenAwake"
    static let planningReminderEnabled = "reasi.settings.planningReminderEnabled"
    static let planningReminderWeekday = "reasi.settings.planningReminderWeekday"
    static let planningReminderHour = "reasi.settings.planningReminderHour"
    static let planningReminderMinute = "reasi.settings.planningReminderMinute"
}

enum WeeklyPlanningDay: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

enum ReasiNotificationPermission: Equatable {
    case unknown
    case allowed
    case denied

    var label: String {
        switch self {
        case .unknown: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Off in iPhone Settings"
        }
    }
}

@MainActor
@Observable
final class UserSettingsStore {
    private(set) var hapticsEnabled: Bool
    private(set) var hideCompletedItems: Bool
    private(set) var keepScreenAwake: Bool
    private(set) var planningReminderEnabled: Bool
    private(set) var planningReminderDay: WeeklyPlanningDay
    private(set) var planningReminderHour: Int
    private(set) var planningReminderMinute: Int
    private(set) var notificationPermission: ReasiNotificationPermission = .unknown
    private(set) var reminderMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationCenter: UNUserNotificationCenter
    @ObservationIgnored private let reminderIdentifier = "ai.reasi.weekly-plan-reminder"

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        hapticsEnabled = Self.bool(defaults, key: ReasiSettingKey.hapticsEnabled, fallback: true)
        hideCompletedItems = Self.bool(defaults, key: ReasiSettingKey.hideCompletedItems, fallback: false)
        keepScreenAwake = Self.bool(defaults, key: ReasiSettingKey.keepScreenAwake, fallback: true)
        planningReminderEnabled = Self.bool(defaults, key: ReasiSettingKey.planningReminderEnabled, fallback: false)
        planningReminderDay = WeeklyPlanningDay(
            rawValue: defaults.integer(forKey: ReasiSettingKey.planningReminderWeekday)
        ) ?? .sunday
        let storedHour = defaults.object(forKey: ReasiSettingKey.planningReminderHour) as? Int
        let storedMinute = defaults.object(forKey: ReasiSettingKey.planningReminderMinute) as? Int
        planningReminderHour = storedHour ?? 17
        planningReminderMinute = storedMinute ?? 0
    }

    var reminderTime: Date {
        Calendar.current.date(
            from: DateComponents(
                calendar: Calendar.current,
                timeZone: .current,
                year: 2001,
                month: 1,
                day: 1,
                hour: planningReminderHour,
                minute: planningReminderMinute
            )
        ) ?? Date()
    }

    var reminderSummary: String {
        guard planningReminderEnabled else { return "Off" }
        let time = reminderTime.formatted(date: .omitted, time: .shortened)
        return "\(planningReminderDay.title) · \(time)"
    }

    var planningReminderMinuteOfDay: Int {
        (planningReminderHour * 60) + planningReminderMinute
    }

    var shoppingBehaviorSummary: String {
        switch (hideCompletedItems, keepScreenAwake) {
        case (true, true): "Hide bought · Screen awake"
        case (true, false): "Hide bought"
        case (false, true): "Screen awake"
        case (false, false): "Standard"
        }
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        defaults.set(enabled, forKey: ReasiSettingKey.hapticsEnabled)
    }

    func setHideCompletedItems(_ enabled: Bool) {
        hideCompletedItems = enabled
        defaults.set(enabled, forKey: ReasiSettingKey.hideCompletedItems)
    }

    func setKeepScreenAwake(_ enabled: Bool) {
        keepScreenAwake = enabled
        defaults.set(enabled, forKey: ReasiSettingKey.keepScreenAwake)
    }

    func setPlanningReminderDay(_ day: WeeklyPlanningDay) {
        planningReminderDay = day
        defaults.set(day.rawValue, forKey: ReasiSettingKey.planningReminderWeekday)
        Task { await rescheduleIfNeeded() }
    }

    func setPlanningReminderTime(minutesFromMidnight: Int) {
        let boundedMinutes = min(max(minutesFromMidnight, 0), (24 * 60) - 1)
        planningReminderHour = boundedMinutes / 60
        planningReminderMinute = boundedMinutes % 60
        defaults.set(planningReminderHour, forKey: ReasiSettingKey.planningReminderHour)
        defaults.set(planningReminderMinute, forKey: ReasiSettingKey.planningReminderMinute)
        Task { await rescheduleIfNeeded() }
    }

    func setPlanningReminderEnabled(_ enabled: Bool) async {
        reminderMessage = nil

        guard enabled else {
            planningReminderEnabled = false
            defaults.set(false, forKey: ReasiSettingKey.planningReminderEnabled)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
            await refreshNotificationPermission()
            return
        }

        do {
            let settings = await notificationCenter.notificationSettings()
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                allowed = true
            case .notDetermined:
                allowed = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            case .denied:
                allowed = false
            @unknown default:
                allowed = false
            }

            guard allowed else {
                planningReminderEnabled = false
                defaults.set(false, forKey: ReasiSettingKey.planningReminderEnabled)
                reminderMessage = "Allow notifications in iPhone Settings to use weekly reminders."
                await refreshNotificationPermission()
                return
            }

            planningReminderEnabled = true
            defaults.set(true, forKey: ReasiSettingKey.planningReminderEnabled)
            try await scheduleReminder()
            reminderMessage = "Your weekly planning reminder is set."
            await refreshNotificationPermission()
        } catch {
            planningReminderEnabled = false
            defaults.set(false, forKey: ReasiSettingKey.planningReminderEnabled)
            reminderMessage = "The reminder could not be scheduled. Please try again."
        }
    }

    func refreshNotificationPermission() async {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationPermission = .allowed
        case .denied:
            notificationPermission = .denied
        case .notDetermined:
            notificationPermission = .unknown
        @unknown default:
            notificationPermission = .unknown
        }
    }

    private func rescheduleIfNeeded() async {
        guard planningReminderEnabled else { return }
        do {
            try await scheduleReminder()
            reminderMessage = "Reminder updated."
        } catch {
            reminderMessage = "The reminder could not be updated. Please try again."
        }
    }

    private func scheduleReminder() async throws {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Ready for an easier week?"
        content.body = "Plan your dinners and shopping route before the week gets busy."
        content.sound = .default

        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = .current
        components.weekday = planningReminderDay.rawValue
        components.hour = planningReminderHour
        components.minute = planningReminderMinute

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try await notificationCenter.add(request)
    }

    private static func bool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
