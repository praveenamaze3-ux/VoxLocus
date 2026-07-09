
import SwiftUI

struct FilterBarView: View {
    @Binding var selectedCategory: NoteCategory?
    @Binding var showOnlyWithTodos: Bool
    @Binding var showOnlyNearby: Bool

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        chip(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(NoteCategory.allCases) { category in
                            chip(title: category.rawValue, systemImage: category.systemImage, isSelected: selectedCategory == category) {
                                selectedCategory = (selectedCategory == category) ? nil : category
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack(spacing: 16) {
                Toggle(isOn: $showOnlyWithTodos) {
                    Label("Has To-Dos", systemImage: "checklist")
                }
                .toggleStyle(.button)
                .tint(AppTheme.accent)
                .font(.caption)

                Toggle(isOn: $showOnlyNearby) {
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
        .background(AppTheme.background)
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
        .glassEffect(
            isSelected ? .regular.tint(AppTheme.accent).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}
#Preview {
    FilterBarView(selectedCategory: .constant(nil), showOnlyWithTodos: .constant(false), showOnlyNearby: .constant(false))
}
