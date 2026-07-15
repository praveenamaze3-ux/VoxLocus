import SwiftUI

/// Menu picker over every `NoteCategory`, showing each case's localized
/// display name and icon — used by both the add- and edit-note forms.
struct CategoryPicker: View {
    @Binding var selection: NoteCategory

    var body: some View {
        Picker("Category", selection: $selection) {
            ForEach(NoteCategory.allCases) { cat in
                Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
            }
        }
        .pickerStyle(.menu)
        .tint(AppTheme.accent)
        .foregroundStyle(AppTheme.textPrimary)
    }
}

/// A note's category name + icon, tinted to match the category — used on
/// note rows and the note detail header. Takes the persisted raw value
/// (rather than `NoteCategory`) since callers work off `NoteEntity.category`.
struct CategoryBadge: View {
    let categoryRawValue: String

    var body: some View {
        Label(
            NoteCategory.displayName(for: categoryRawValue),
            systemImage: NoteCategory(rawValue: categoryRawValue)?.systemImage ?? "tag"
        )
        .foregroundStyle(AppTheme.categoryColor(for: categoryRawValue))
    }
}
