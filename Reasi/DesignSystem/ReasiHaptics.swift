import UIKit

@MainActor
enum ReasiHaptics {
    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: ReasiSettingKey.hapticsEnabled) as? Bool ?? true
    }
}
