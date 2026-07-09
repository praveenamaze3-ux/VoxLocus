import SwiftUI
enum AppTheme {

    // MARK: - Core palette (Indigo / Blue)

    /// Deep indigo-navy — primary background
    static let background     = Color(hex: "#0A0E1F")
    /// Slightly lifted indigo — card / list row background
    static let surface        = Color(hex: "#131A33")
    /// Raised card surface for sheets and modals
    static let surfaceRaised  = Color(hex: "#1B2545")
    /// Vivid indigo-blue — primary brand accent (buttons, active states)
    static let accent         = Color(hex: "#5E6AD2")
    /// Coral red — recording active state
    static let recordingRed   = Color(hex: "#FF6B5B")
    /// Warm amber — Save action
    static let saveAmber      = Color(hex: "#F5B942")
    /// Emerald — success / synced (kept distinct from the indigo accent)
    static let success        = Color(hex: "#34D399")
    /// Muted blue-gray — secondary text
    static let textSecondary  = Color(hex: "#9BA4C4")
    /// Cool off-white — primary text
    static let textPrimary    = Color(hex: "#F1F3FC")
    /// Muted indigo-gray border
    static let border         = Color(hex: "#2A3358")

    // MARK: - Semantic shorthands

    static let categoryColors: [String: Color] = [
        "Personal":  Color(hex: "#5E6AD2"),
        "Work":      Color(hex: "#4AA8D8"),
        "Shopping":  Color(hex: "#F5B942"),
        "Health":    Color(hex: "#FF6B5B"),
        "Ideas":     Color(hex: "#D4C86A"),
        "Other":     Color(hex: "#9BA4C4")
    ]

    static func categoryColor(for category: String) -> Color {
        categoryColors[category] ?? textSecondary
    }
}

// MARK: - Hex color initialiser
//extract RGB patterns via bit shifting .
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Reusable themed card modifier (Liquid Glass)

struct ThemedCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .glassEffect(
                .regular.tint(AppTheme.surface.opacity(0.55)),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 0.5)
            )
    }
}

extension View {
    func themedCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ThemedCard(cornerRadius: cornerRadius))
    }
}
