import SwiftUI

struct ReasiProfileButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            ReasiHaptics.light()
            action()
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.reasi.textMuted)
                .frame(width: 48, height: 48)
                .background(Color.reasi.surface, in: Circle())
                .overlay {
                    Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                }
        }
        .buttonStyle(ReasiPressStyle())
        .accessibilityLabel("Open profile and settings")
        .accessibilityIdentifier("reasi-profile-button")
    }
}

/// A toolbar button on a tab's root screen, next to the profile button.
struct ReasiToolbarAction {
    let title: String
    let systemImage: String
    var identifier: String? = nil
    let perform: () -> Void
}

extension View {
    /// The standard top of every tab: a native large title, an optional subtitle, an optional
    /// action and the profile button, all in the system navigation bar.
    func reasiTabRoot(
        _ title: String,
        subtitle: String? = nil,
        action: ReasiToolbarAction? = nil,
        openProfile: @escaping () -> Void
    ) -> some View {
        modifier(ReasiTabRootModifier(title: title, subtitle: subtitle, action: action, openProfile: openProfile))
    }
}

private struct ReasiTabRootModifier: ViewModifier {
    let title: String
    let subtitle: String?
    let action: ReasiToolbarAction?
    let openProfile: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let action {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action.title, systemImage: action.systemImage) {
                            ReasiHaptics.light()
                            action.perform()
                        }
                        .accessibilityIdentifier(action.identifier ?? "")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Open profile and settings", systemImage: "person.crop.circle") {
                        ReasiHaptics.light()
                        openProfile()
                    }
                    .accessibilityIdentifier("reasi-profile-button")
                }
            }
    }
}
