import SwiftUI

/// Compact red banner used to surface a save/validation error under a form.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message).font(.caption)
        }
        .foregroundStyle(AppTheme.recordingRed)
        .padding(12)
        .background(AppTheme.recordingRed.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.recordingRed.opacity(0.4), lineWidth: 0.5)
        )
    }
}
