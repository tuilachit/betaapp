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
