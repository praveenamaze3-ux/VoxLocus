//
//  EditNoteView.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//
//
//  EditNoteView.swift
//  SmartNotes
//
//  Full editing screen for an existing note. Lets the user:
//    • Edit the transcript text
//    • Change the category
//    • Toggle todo completion / add / delete todos
//    • Re-run NLP extraction on the edited text
//  On save: re-encrypts the payload, updates Core Data, and re-syncs to Firebase.
//
import SwiftUI
import MapKit

struct EditNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationService: LocationGeofenceService

    @State private var transcript: String
    @State private var selectedCategory: NoteCategory
    @State private var todos: [TodoItem]
    @State private var selectedLocation: LocationResult?
    @State private var showLocationSearch = false
    @State private var isExtracting = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let note: NoteEntity
    private let viewModel: NotesListViewModel

    init(note: NoteEntity, viewModel: NotesListViewModel) {
        self.note      = note
        self.viewModel = viewModel
        _transcript       = State(initialValue: note.safeTranscript)
        _selectedCategory = State(initialValue: NoteCategory(rawValue: note.safeCategory) ?? .other)
        _todos            = State(initialValue: note.safeTodos)

        // Pre-populate location if one was saved
        if note.isAccessible,
           note.latitude != 0 || note.longitude != 0,
           let name = note.locationName, !name.isEmpty {
            _selectedLocation = State(initialValue: LocationResult(
                name: name,
                subtitle: "",
                coordinate: CLLocationCoordinate2D(
                    latitude: note.latitude,
                    longitude: note.longitude
                )
            ))
        } else {
            _selectedLocation = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Transcript
                Section("Note") {
                    TextEditor(text: $transcript)
                        .frame(minHeight: 160)
                }

                // MARK: Category
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(NoteCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        selectedCategory = NLPTodoExtractor.suggestCategory(for: transcript)
                    } label: {
                        Label("Auto-suggest from text", systemImage: "sparkles")
                    }
                    .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // MARK: Location
                Section {
                    if let loc = selectedLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.name)
                                        .font(.body.bold())
                                    if !loc.subtitle.isEmpty {
                                        Text(loc.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Button {
                                    selectedLocation = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Map(position: .constant(
                                .region(MKCoordinateRegion(
                                    center: loc.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                ))
                            )) {
                                Marker(loc.name, coordinate: loc.coordinate)
                            }
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(true)
                        }
                        .padding(.vertical, 4)

                        Button("Change Location") { showLocationSearch = true }
                            .foregroundStyle(.blue)
                    } else {
                        Button {
                            showLocationSearch = true
                        } label: {
                            Label("Add Location", systemImage: "mappin.and.ellipse")
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Notes with a location will be suggested when you're nearby.")
                        .font(.caption)
                }

                // MARK: To-Dos
                Section {
                    ForEach($todos) { $todo in
                        HStack(spacing: 12) {
                            Button { todo.isCompleted.toggle() } label: {
                                Image(systemName: todo.isCompleted
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            TextField("To-do", text: $todo.text)
                        }
                    }
                    .onDelete { todos.remove(atOffsets: $0) }
                    .onMove  { todos.move(fromOffsets: $0, toOffset: $1) }

                    Button { todos.append(TodoItem(text: "")) } label: {
                        Label("Add To-Do", systemImage: "plus.circle")
                    }
                    Button {
                        reExtractTodos()
                    } label: {
                        Label(isExtracting ? "Extracting…" : "Re-extract via NLP",
                              systemImage: "wand.and.stars")
                    }
                    .disabled(isExtracting || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    HStack {
                        Text("To-Dos")
                        Spacer()
                        EditButton().font(.caption)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .dismissWhenDeleted(note)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { saveEdits() }
                        .disabled(isSaving || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { result in
                    selectedLocation = result
                }
                .environmentObject(locationService)
            }
        }
    }

    // MARK: - Actions

    private func reExtractTodos() {
        isExtracting = true
        Task {
            let extracted = await NLPTodoExtractor.extractTodos(from: transcript)
            let existingTexts = Set(todos.map { $0.text.lowercased() })
            let newOnes = extracted.filter { !existingTexts.contains($0.text.lowercased()) }
            todos.append(contentsOf: newOnes)
            isExtracting = false
        }
    }

    private func saveEdits() {
        isSaving = true
        errorMessage = nil
        let updatedTranscript = transcript
        let updatedCategory   = selectedCategory
        let updatedTodos      = todos.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let updatedLocation   = selectedLocation

        Task {
            do {
                // Remove old geofence
                locationService.removeGeofence(noteID: note.id)

                try await viewModel.updateNote(
                    note,
                    transcript: updatedTranscript,
                    category: updatedCategory,
                    todos: updatedTodos,
                    location: updatedLocation
                )

                // Register new geofence if a location was set
                if let loc = updatedLocation {
                    let dto = NoteDTO(
                        id: note.id,
                        transcript: updatedTranscript,
                        createdAt: note.safeCreatedAt,
                        category: updatedCategory.rawValue,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        locationName: loc.name,
                        todos: updatedTodos
                    )
                    locationService.registerGeofence(for: dto)
                }

                await MainActor.run { isSaving = false; dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
