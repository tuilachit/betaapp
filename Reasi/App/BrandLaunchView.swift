import SwiftUI

struct BrandLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var bloomProgress: CGFloat = 0.01
    @State private var wordmarkOpacity = 0.0
    @State private var wordmarkScale = 0.82
    @State private var wordmarkBlur = 12.0
    @State private var wordmarkOffsetX: CGFloat = -8
    @State private var screenOpacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            let wordmarkWidth = min(proxy.size.width * 0.88, 360)
            let wordmarkHeight = wordmarkWidth * 0.34

            ZStack {
                Color.reasi.background

                wordmark(width: wordmarkWidth, height: wordmarkHeight)
                    .mask {
                        radialRevealMask(
                            width: wordmarkWidth,
                            height: wordmarkHeight,
                            progress: bloomProgress
                        )
                    }
                    .padding(24)
                    .opacity(wordmarkOpacity)
                    .blur(radius: wordmarkBlur)
                    .scaleEffect(wordmarkScale)
                    .offset(x: wordmarkOffsetX)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * 0.48
                    )
            }
            .ignoresSafeArea()
        }
        .opacity(screenOpacity)
        .accessibilityHidden(true)
        .task {
            await playIntro()
        }
    }

    private func wordmark(width: CGFloat, height: CGFloat) -> some View {
        Image("ReasiWordmark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .foregroundStyle(Color.reasi.text)
    }

    private func radialRevealMask(
        width: CGFloat,
        height: CGFloat,
        progress: CGFloat
    ) -> some View {
        let clampedProgress = min(max(progress, 0.001), 1.08)
        let diameter = width * 1.18
        let edgeBlur = max(1, 11 * (1 - min(clampedProgress, 1)))

        return ZStack {
            Circle()
                .frame(width: diameter, height: diameter)
                .scaleEffect(clampedProgress)
                .blur(radius: edgeBlur)
        }
        .frame(width: width, height: height)
    }

    @MainActor
    private func playIntro() async {
        if reduceMotion {
            bloomProgress = 1.08
            wordmarkOpacity = 1
            wordmarkScale = 1
            wordmarkBlur = 0
            wordmarkOffsetX = 0

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                wordmarkOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(130))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.15)) {
                screenOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }

        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) {
            bloomProgress = 0.16
            wordmarkOpacity = 0.62
            wordmarkScale = 0.88
            wordmarkBlur = 10
        }

        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }

        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.68)) {
            bloomProgress = 1.08
            wordmarkOpacity = 1
            wordmarkScale = 1
            wordmarkBlur = 0
            wordmarkOffsetX = 0
        }

        try? await Task.sleep(for: .milliseconds(890))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            wordmarkScale = 1.025
            wordmarkOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            screenOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

#Preview {
    BrandLaunchView(onFinished: {})
        .preferredColorScheme(.dark)
}
