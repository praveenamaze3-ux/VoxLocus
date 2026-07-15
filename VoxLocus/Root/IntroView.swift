import SwiftUI

/// Animated splash shown once per app launch, before the auth/recording flow.
/// Purely presentational — calls `onFinished` when its entrance animation
/// has played out so the caller can swap it for the real content.
struct IntroView: View {
    var onFinished: () -> Void

    @State private var ringScale: CGFloat = 0.75
    @State private var ringOpacity: Double = 0.6
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var titleOffset: CGFloat = 16
    @State private var titleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    var body: some View {
        ZStack {
            GradientBackground()
            pulsingRing
            VStack(spacing: 14) {
                logoMark
                title
                tagline
            }
        }
        .onAppear(perform: animate)
    }

    // MARK: - Pieces

    private var pulsingRing: some View {
        Circle()
            .stroke(AppTheme.accent.opacity(0.35), lineWidth: 2)
            .frame(width: 150, height: 150)
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
    }

    private var logoMark: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(width: 104, height: 104)
            Image(systemName: "mic.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }

    private var title: some View {
        Text("VoxLocus")
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .offset(y: titleOffset)
            .opacity(titleOpacity)
    }

    private var tagline: some View {
        Text("Speak it. Remember it. Right where you are.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .opacity(taglineOpacity)
    }

    private func animate() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
            titleOffset = 0
            titleOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            taglineOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 1.1).delay(0.15)) {
            ringScale = 1.35
            ringOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            onFinished()
        }
    }
}

#Preview {
    IntroView(onFinished: {})
}
