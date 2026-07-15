import SwiftUI

/// Full-width prominent "Save" button that swaps its icon for a spinner and
/// its title for a "Saving…" label while a save is in flight — used by both
/// the add- and edit-note forms.
struct SaveActionButton: View {
    let idleTitle: LocalizedStringKey
    let systemImage: String
    let isSaving: Bool
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isSaving { ProgressView() } else { Image(systemName: systemImage) }
                Text(isSaving ? "Saving…" : idleTitle).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(disabled)
    }
}

/// Full-width `Label` button styled to match the recording screen's glass
/// action buttons — collapses what were three near-identical button blocks
/// (Start/Stop, Pause/Resume, Save) into one parameterized view.
struct FullWidthLabelButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var prominent: Bool = true
    let tint: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) { labelContent }
                    .buttonStyle(.glassProminent)
            } else {
                Button(action: action) { labelContent }
                    .buttonStyle(.glass)
            }
        }
        .tint(tint)
        .disabled(disabled)
    }

    private var labelContent: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
    }
}
