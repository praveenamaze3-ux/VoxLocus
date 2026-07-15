import SwiftUI

extension View {
    /// The app's standard nav-bar treatment for full-screen sheets: an
    /// inline title with a dark-styled bar — used by every add/edit/detail
    /// sheet in the app.
    func compactDarkNavBar() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// The leading "Cancel" toolbar item shared by every sheet that can be
/// dismissed without saving.
@ToolbarContentBuilder
func cancelToolbarItem(disabled: Bool = false, action: @escaping () -> Void) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", action: action)
            .foregroundStyle(AppTheme.textSecondary)
            .disabled(disabled)
    }
}
