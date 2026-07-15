import SwiftUI

/// A tappable row used both for the "use current location" shortcut and
/// each search result in `LocationSearchView`: a tinted circular icon,
/// name/subtitle, and a trailing chevron.
struct LocationResultRow: View {
    let iconName: String
    let iconTint: Color
    let title: String
    let titleColor: Color
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .foregroundStyle(iconTint)
                        .font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.bold())
                        .foregroundStyle(titleColor)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(.caption)
            }
            .padding(14)
            .themedCard()
        }
        .buttonStyle(.plain)
    }
}
