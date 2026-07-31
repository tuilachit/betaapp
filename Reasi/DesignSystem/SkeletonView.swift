import SwiftUI

struct SkeletonBlock: View {
    var height: CGFloat
    var radius: CGFloat = ReasiRadius.lg
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.reasi.surfaceHigh)
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.reasi.text.opacity(0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: proxy.size.width * 0.75)
                    .offset(x: shimmerOffset * proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .onAppear {
                shimmerOffset = -1
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.6
                }
            }
            .accessibilityHidden(true)
    }
}

struct GenerationProgressCard: View {
    let stage: WeekPlanGenerationStage
    let elapsedSeconds: Int
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ReasiSpacing.s4) {
            HStack(alignment: .top, spacing: ReasiSpacing.s3) {
                ProgressView()
                    .tint(Color.reasi.text)
                    .controlSize(.small)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(ReasiTypography.headline)
                        .foregroundStyle(Color.reasi.text)
                    Text(stage.detail)
                        .font(ReasiTypography.callout)
                        .foregroundStyle(Color.reasi.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ReasiSpacing.s2)

                if elapsedSeconds >= 5 {
                    Text("\(elapsedSeconds)s")
                        .font(ReasiTypography.caption)
                        .foregroundStyle(Color.reasi.muted)
                        .monospacedDigit()
                }
            }

            Button(action: cancel) {
                Label("Cancel", systemImage: "xmark")
                    .font(ReasiTypography.bodyMedium)
                    .foregroundStyle(Color.reasi.textMuted)
            }
            .buttonStyle(ReasiPressStyle())
        }
        .padding(ReasiSpacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.reasi.surface, in: RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReasiRadius.xl, style: .continuous)
                .stroke(Color.reasi.border, lineWidth: 1)
        }
        .animation(ReasiMotion.fast, value: stage)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: ReasiSpacing.s4) {
        SkeletonBlock(height: 120)
        SkeletonBlock(height: 56, radius: ReasiRadius.md)
        SkeletonBlock(height: 56, radius: ReasiRadius.md)
    }
    .padding()
    .background(Color.reasi.background)
}
