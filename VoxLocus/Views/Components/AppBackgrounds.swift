import SwiftUI

/// Solid theme-background layer, ignoring safe areas — the base `ZStack`
/// layer used by every full-screen sheet/detail view in the app.
struct ScreenBackground: View {
    var body: some View {
        AppTheme.background.ignoresSafeArea()
    }
}

/// Top-to-bottom theme gradient background, ignoring safe areas — used by
/// the top-level auth, notes-list, and intro screens.
struct GradientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.background, AppTheme.surfaceRaised],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
