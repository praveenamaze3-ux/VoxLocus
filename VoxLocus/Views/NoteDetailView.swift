//
//  NoteDetailView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//  NoteDetailView.swift
//  SmartNotes
//

import SwiftUI
internal import CoreData

struct NoteDetailView: View {
    @ObservedObject var note: NoteEntity
    @ObservedObject var viewModel: NotesListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false

    private var isNoteValid: Bool {
        !note.isDeleted && note.managedObjectContext != nil
    }

    var body: some View {
        Group {
            if isNoteValid {
                noteContent
            } else {
                ContentUnavailableView(
                    "Note Deleted",
                    systemImage: "trash",
                    description: Text("This note has been removed.")
                )
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(!isNoteValid)
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditNoteView(note: note, viewModel: viewModel)
                .environmentObject(LocationGeofenceService())
        }
        .onChange(of: note.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
    }

    private var noteContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Header
                HStack {
                    if let category = note.category,
                       let cat = NoteCategory(rawValue: category) {
                        Label(cat.rawValue, systemImage: cat.systemImage)
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    // Safely unwrap createdAt — Core Data stores it as
                    // optional at the ObjC layer even if Swift says non-optional.
                    if note.managedObjectContext != nil {
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Transcript
                Text(note.transcript ?? "No transcript available.")
                    .font(.body)

                // MARK: Location
                if let location = note.locationName, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: To-Dos
                if !note.todos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To-Dos (synced to Reminders)")
                            .font(.headline)
                        ForEach(note.todos) { todo in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: todo.isCompleted
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
                                Text(todo.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }

                // MARK: Sync status
                Label(
                    note.isSyncedToCloud
                        ? "Synced & encrypted in cloud"
                        : "Pending encrypted sync",
                    systemImage: note.isSyncedToCloud
                        ? "lock.icloud.fill"
                        : "icloud.and.arrow.up"
                )
                .font(.caption)
                .foregroundStyle(note.isSyncedToCloud ? .green : .orange)

                // MARK: Delete
                Button(role: .destructive) {
                    viewModel.delete(note)
                    dismiss()
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
                .padding(.top, 12)
            }
            .padding()
        }
    }
}
