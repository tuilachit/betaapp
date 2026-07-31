import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var primaryAction: () -> Void
    @Namespace private var activeNamespace

    var body: some View {
        GeometryReader { proxy in
            let plusSize: CGFloat = 70
            let dockSpacing = ReasiSpacing.s2
            let dockWidth = max(0, proxy.size.width - plusSize - dockSpacing)

            HStack(spacing: dockSpacing) {
                HStack(spacing: ReasiSpacing.s1) {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            guard selectedTab != tab else { return }
                            ReasiHaptics.selection()
                            selectedTab = tab
                        } label: {
                            tabItem(tab)
                        }
                        .buttonStyle(ReasiPressStyle())
                        .accessibilityLabel(tab.title)
                    }
                }
                .padding(ReasiSpacing.s1)
                .frame(width: dockWidth, height: plusSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                .background(Color.reasi.glass, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                        .stroke(Color.reasi.borderStrong, lineWidth: 1)
                }

                Button {
                    ReasiHaptics.light()
                    primaryAction()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.reasi.text)
                        .frame(width: plusSize, height: plusSize)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.reasi.glass, in: Circle())
                        .overlay {
                            Circle().stroke(Color.reasi.borderStrong, lineWidth: 1)
                        }
                }
                .buttonStyle(ReasiPressStyle())
                .accessibilityLabel("Create new")
            }
        }
        .frame(height: 70)
        .padding(.horizontal, ReasiSpacing.s5)
        .padding(.bottom, ReasiSpacing.s3)
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return VStack(spacing: 3) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 19, weight: .semibold))
            Text(tab.title)
                .font(ReasiTypography.navLabel)
        }
        .foregroundStyle(isSelected ? Color.reasi.text : Color.reasi.muted)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58)
        .padding(.horizontal, ReasiSpacing.s2)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.reasi.surfaceHigh)
                    .matchedGeometryEffect(id: "active-tab", in: activeNamespace)
            }
        }
        .animation(ReasiMotion.tactileSpring, value: selectedTab)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var tab: AppTab = .home

        var body: some View {
            ZStack(alignment: .bottom) {
                Color.reasi.background.ignoresSafeArea()
                FloatingTabBar(selectedTab: $tab) {}
            }
        }
    }

    return PreviewWrapper()
}
