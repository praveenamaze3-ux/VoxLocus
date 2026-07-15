import SwiftUI

/// A titled, icon-labeled card used to group a control (text editor, picker,
/// location, etc.) inside the add/edit note forms, with an optional caption
/// footer underneath.
struct ThemedSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let footer: LocalizedStringKey?
    let content: Content

    init(
        title: LocalizedStringKey,
        icon: String,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            content
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .themedCard()
    }
}
