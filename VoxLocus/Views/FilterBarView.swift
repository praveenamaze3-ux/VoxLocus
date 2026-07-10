
import SwiftUI

struct FilterBarView: View {
    @Binding var selectedCategory: NoteCategory?
    @Binding var showOnlyWithTodos: Bool
    @Binding var showOnlyNearby: Bool

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "All", isSelected: selectedCategory == nil) {
                        withAnimation(.easeInOut(duration: 0.25)) { selectedCategory = nil }
                    }
                    ForEach(NoteCategory.allCases) { category in
                        chip(title: category.rawValue, systemImage: category.systemImage, isSelected: selectedCategory == category) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedCategory = (selectedCategory == category) ? nil : category
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Toggle(isOn: animatedBinding($showOnlyWithTodos)) {
                    Label("Has To-Dos", systemImage: "checklist")
                }
                .toggleStyle(.button)
                .tint(AppTheme.accent)
                .font(.caption)

                Toggle(isOn: animatedBinding($showOnlyNearby)) {
                    Label("Nearby", systemImage: "location.fill")
                }
                .toggleStyle(.button)
                .tint(AppTheme.accent)
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 6)
        .background(AppTheme.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border.opacity(0.6))
                .frame(height: 0.5)
        }
    }

    /// Wraps a toggle binding so flipping it animates the resulting list change.
    private func animatedBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in withAnimation(.easeInOut(duration: 0.25)) { binding.wrappedValue = newValue } }
        )
    }

    private func chip(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .background(isSelected ? AppTheme.accent : AppTheme.surface, in: .capsule)
        .overlay(
            Capsule().strokeBorder(AppTheme.border, lineWidth: isSelected ? 0 : 0.5)
        )
    }
}
#Preview {
    FilterBarView(selectedCategory: .constant(nil), showOnlyWithTodos: .constant(false), showOnlyNearby: .constant(false))
}
