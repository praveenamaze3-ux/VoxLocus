//
//  NoteListView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//  NotesListView.swift
//  SmartNotes
//
import SwiftUI
internal import CoreData

struct NotesListView: View {
    @StateObject var viewModel: NotesListViewModel
    @EnvironmentObject var locationService: LocationGeofenceService
    @State private var showingAddNote = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.nearbySuggestions.isEmpty {
                    nearbyBanner
                }
                FilterBarView(
                    selectedCategory: $viewModel.selectedCategory,
                    showOnlyWithTodos: $viewModel.showOnlyWithTodos,
                    showOnlyNearby: $viewModel.showOnlyNearby
                )

                List {
                    ForEach(viewModel.filteredNotes) { note in
                        NavigationLink {
                            NoteDetailView(note: note, viewModel: viewModel)
                        } label: {
                            NoteRow(note: note)
                        }
                    }
                    .onDelete { indices in
                        for index in indices {
                            viewModel.delete(viewModel.filteredNotes[index])
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $viewModel.searchText, prompt: "Search notes")
                .overlay {
                    if viewModel.filteredNotes.isEmpty {
                        ContentUnavailableView("No Notes Yet", systemImage: "note.text", description: Text("Tap + to add a note, or record one from the Record tab."))
                    }
                }
            }
            .navigationTitle("Smart Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddNote) {
                AddNoteView()
                    .environmentObject(locationService)
            }
        }
    }

    private var nearbyBanner: some View {
        HStack {
            Image(systemName: "location.fill")
            Text("You're near a place with \(viewModel.nearbySuggestions.count) saved note(s).")
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(.yellow.opacity(0.25))
    }
}

private struct NoteRow: View {
    @ObservedObject var note: NoteEntity

    private var isValid: Bool {
        !note.isDeleted && note.managedObjectContext != nil
    }

    var body: some View {
        if isValid {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let category = note.category {
                        Label(category, systemImage: NoteCategory(rawValue: category)?.systemImage ?? "tag")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text(note.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(note.transcript ?? "")
                    .font(.body)
                    .lineLimit(2)
                if !note.todos.isEmpty {
                    Label("\(note.todos.count) to-do(s)", systemImage: "checklist")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if !note.isSyncedToCloud {
                    Label("Pending sync", systemImage: "icloud.and.arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        } else {
            EmptyView()
        }
    }
}

#Preview {
    NotesListView(viewModel: NotesListViewModel(
        context: PersistenceController.preview.container.viewContext,
        locationService: LocationGeofenceService()
    ))
}
