import SwiftUI

struct NoteDetailView: View {
    @ObservedObject var note: NoteEntity
    @ObservedObject var viewModel: NotesListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var showingEdit       = false

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    noteCard
                    if !note.todos.isEmpty {
                        todosCard
                    }
                    syncStatusLabel
                    deleteButton
                }
                .padding()
            }
        }
        .navigationTitle("Note")
        .compactDarkNavBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEdit = true }
                    .tint(AppTheme.accent)
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditNoteView(note: note, viewModel: viewModel)
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.delete(note)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the note from this device and the cloud.")
        }
    }

    // MARK: - Note card (category, title, transcript, location)

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            noteHeader
            Text(note.displayTitle)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Divider().background(AppTheme.border)
            Text(note.transcript ?? "")
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
            if let location = note.locationName, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding()
        .themedCard()
    }

    private var noteHeader: some View {
        HStack {
            if let category = note.category {
                CategoryBadge(categoryRawValue: category)
                    .font(.subheadline.bold())
            }
            Spacer()
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - To-Dos (original feature, unchanged)

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To-Dos (synced to Reminders)")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            ForEach(note.todos) { todo in
                HStack {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? AppTheme.success : AppTheme.textSecondary)
                    Text(todo.text)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
        .padding()
        .themedCard()
    }

    // MARK: - Sync status

    private var syncStatusLabel: some View {
        Label(
            note.isSyncedToCloud ? "Synced & encrypted in cloud" : "Pending encrypted sync",
            systemImage: note.isSyncedToCloud ? "lock.icloud.fill" : "icloud.and.arrow.up"
        )
        .font(.caption)
        .foregroundStyle(note.isSyncedToCloud ? AppTheme.success : AppTheme.saveAmber)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete Note", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .tint(AppTheme.recordingRed)
        .padding(.top, 4)
    }
}
