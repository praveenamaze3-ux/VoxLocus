import SwiftUI

enum AppTheme {

    // MARK: - Core palette

    /// Deep midnight indigo — primary background
    static let background     = Color(hex: "#0D0F2B")
    /// Slightly lifted indigo — card / list row background
    static let surface        = Color(hex: "#161938")
    /// Raised card surface for sheets and modals
    static let surfaceRaised  = Color(hex: "#1F2347")
    /// Electric violet — primary brand accent (buttons, active states)
    static let accent         = Color(hex: "#7C5CFC")
    /// Coral red — recording active state
    static let recordingRed   = Color(hex: "#FF5F6D")
    /// Warm amber — Save action
    static let saveAmber      = Color(hex: "#FFC947")
    /// Teal — success / synced
    static let success        = Color(hex: "#4ECDC4")
    /// Soft lavender — secondary text
    static let textSecondary  = Color(hex: "#9B98C4")
    /// Near-white warm cream — primary text
    static let textPrimary    = Color(hex: "#F0EEFF")
    /// Muted surface border
    static let border         = Color(hex: "#2A2D5A")

    // MARK: - Semantic shorthands

    static let categoryColors: [String: Color] = [
        "Personal":  Color(hex: "#7C5CFC"),
        "Work":      Color(hex: "#4ECDC4"),
        "Shopping":  Color(hex: "#FFC947"),
        "Health":    Color(hex: "#FF5F6D"),
        "Ideas":     Color(hex: "#A78BFA"),
        "Other":     Color(hex: "#9B98C4")
    ]

    static func categoryColor(for category: String) -> Color {
        categoryColors[category] ?? textSecondary
    }
}

// MARK: - Hex color initialiser

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

// MARK: - Reusable themed card modifier

struct ThemedCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppTheme.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func themedCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ThemedCard(cornerRadius: cornerRadius))
    }
}
