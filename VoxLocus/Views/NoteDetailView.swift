import SwiftUI

struct NoteDetailView: View {
    @ObservedObject var note: NoteEntity
    @ObservedObject var viewModel: NotesListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var showingEdit       = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 16) {
                        // Header: category + date
                        HStack {
                            if let category = note.category {
                                Label(category, systemImage: NoteCategory(rawValue: category)?.systemImage ?? "tag")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.categoryColor(for: category))
                            }
                            Spacer()
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Text(note.displayTitle)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.textPrimary)

                        Divider().background(AppTheme.border)

                        Text(note.transcript ?? "")
                            .font(.body)
                            .foregroundStyle(AppTheme.textPrimary)

                        // Location
                        if let location = note.locationName, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .padding()
                    .themedCard()

                    // To-Dos (original feature, unchanged)
                    if !note.todos.isEmpty {
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

                    // Sync status
                    Label(
                        note.isSyncedToCloud ? "Synced & encrypted in cloud" : "Pending encrypted sync",
                        systemImage: note.isSyncedToCloud ? "lock.icloud.fill" : "icloud.and.arrow.up"
                    )
                    .font(.caption)
                    .foregroundStyle(note.isSyncedToCloud ? AppTheme.success : AppTheme.saveAmber)

                    // Delete
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
                .padding()
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
}
