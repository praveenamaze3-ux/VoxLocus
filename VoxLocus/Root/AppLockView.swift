import SwiftUI

/// Full-screen biometric gate shown as an overlay above `ContentView` while
/// `RootViewModel.isAppLocked` is true. Unlike `IntroView` (a one-shot splash
/// that gets swapped out), this view is repeatedly shown/hidden without ever
/// tearing down what's underneath.
struct AppLockView: View {
    let kind: BiometricAuthService.Kind
    let isAuthenticating: Bool
    let errorMessage: String?
    let onUnlockTapped: () -> Void
    let onSignOutTapped: () -> Void

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 18) {
                iconMark
                Text("VoxLocus Locked")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Use \(kind.displayName) or your device passcode to unlock and view your notes.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.recordingRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                FullWidthLabelButton(
                    title: isAuthenticating
                        ? LocalizedStringKey("Authenticating…")
                        : LocalizedStringKey("Unlock with \(kind.displayName)"),
                    systemImage: kind.systemImage,
                    tint: AppTheme.accent,
                    disabled: isAuthenticating,
                    action: onUnlockTapped
                )
                .padding(.horizontal, 40)
                .padding(.top, 8)

                Button("Sign Out Instead", role: .destructive, action: onSignOutTapped)
                    .font(.footnote)
                    .padding(.top, 4)
            }
        }
    }

    private var iconMark: some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.18)).frame(width: 104, height: 104)
            Image(systemName: kind.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
    }
}

#Preview {
    AppLockView(kind: .faceID, isAuthenticating: false, errorMessage: nil, onUnlockTapped: {}, onSignOutTapped: {})
}
