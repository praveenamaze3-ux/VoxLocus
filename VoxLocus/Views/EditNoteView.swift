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
        self.note = note; self.viewModel = viewModel
        _transcript       = State(initialValue: note.safeTranscript)
        _selectedCategory = State(initialValue: NoteCategory(rawValue: note.safeCategory) ?? .other)
        _todos            = State(initialValue: note.safeTodos)
        if note.isAccessible, note.latitude != 0 || note.longitude != 0,
           let name = note.locationName, !name.isEmpty {
            _selectedLocation = State(initialValue: LocationResult(
                name: name, subtitle: "",
                coordinate: CLLocationCoordinate2D(latitude: note.latitude, longitude: note.longitude)
            ))
        } else { _selectedLocation = State(initialValue: nil) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Transcript
                        themedSection(title: "Note", icon: "square.and.pencil") {
                            TextEditor(text: $transcript)
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        // MARK: Category
                        themedSection(title: "Category", icon: "tag.fill") {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(NoteCategory.allCases) { cat in
                                    Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppTheme.accent)

                            Button {
                                selectedCategory = NLPTodoExtractor.suggestCategory(for: transcript)
                            } label: {
                                Label("Auto-suggest from text", systemImage: "sparkles")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        // MARK: Location
                        themedSection(title: "Location", icon: "mappin.and.ellipse",
                                      footer: "Notes with a location will be suggested when you're nearby.") {
                            if let loc = selectedLocation {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundStyle(AppTheme.recordingRed)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(loc.name)
                                                .font(.body.bold())
                                                .foregroundStyle(AppTheme.textPrimary)
                                            if !loc.subtitle.isEmpty {
                                                Text(loc.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Button { selectedLocation = nil } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }.buttonStyle(.plain)
                                    }
                                    Map(position: .constant(.region(MKCoordinateRegion(
                                        center: loc.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )))) {
                                        Marker(loc.name, coordinate: loc.coordinate)
                                            .tint(AppTheme.recordingRed)
                                    }
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .disabled(true)

                                    Button("Change Location") { showLocationSearch = true }
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.accent)
                                }
                            } else {
                                Button { showLocationSearch = true } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Location")
                                    }
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.accent.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // MARK: To-Dos
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("TO-DOS", systemImage: "checklist")
                                    .font(.caption.bold())
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                EditButton()
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                            }

                            ForEach($todos) { $todo in
                                HStack(spacing: 12) {
                                    Button { todo.isCompleted.toggle() } label: {
                                        Image(systemName: todo.isCompleted
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(todo.isCompleted
                                                             ? AppTheme.success : AppTheme.textSecondary)
                                    }.buttonStyle(.plain)
                                    TextField("To-do", text: $todo.text)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                                .padding(.vertical, 4)
                                Divider().background(AppTheme.border)
                            }
                            .onDelete { todos.remove(atOffsets: $0) }
                            .onMove  { todos.move(fromOffsets: $0, toOffset: $1) }

                            HStack(spacing: 12) {
                                Button {
                                    todos.append(TodoItem(text: ""))
                                } label: {
                                    Label("Add To-Do", systemImage: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.accent)
                                }
                                Spacer()
                                Button {
                                    reExtractTodos()
                                } label: {
                                    Label(isExtracting ? "Extracting…" : "Re-extract via NLP",
                                          systemImage: "wand.and.stars")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .disabled(isExtracting || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(14)
                        .themedCard()

                        // MARK: Error
                        if let errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(errorMessage).font(.caption)
                            }
                            .foregroundStyle(AppTheme.recordingRed)
                            .padding(12)
                            .background(AppTheme.recordingRed.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }

                        // MARK: Save button
                        Button { saveEdits() } label: {
                            HStack {
                                if isSaving { ProgressView().tint(AppTheme.background) }
                                else { Image(systemName: "checkmark.circle.fill") }
                                Text(isSaving ? "Saving…" : "Save Changes").font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isSaving ? AppTheme.accent.opacity(0.4) : AppTheme.accent,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(.white)
                        }
                        .disabled(isSaving || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .dismissWhenDeleted(note)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                        .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { result in selectedLocation = result }
                    .environmentObject(locationService)
            }
        }
    }

    // MARK: - Themed section builder

    @ViewBuilder
    private func themedSection<Content: View>(
        title: String, icon: String, footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            content()
            if let footer {
                Text(footer).font(.caption2).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .themedCard()
    }

    // MARK: - Actions

    private func reExtractTodos() {
        isExtracting = true
        Task {
            let extracted = await NLPTodoExtractor.extractTodos(from: transcript)
            let existing  = Set(todos.map { $0.text.lowercased() })
            todos.append(contentsOf: extracted.filter { !existing.contains($0.text.lowercased()) })
            isExtracting = false
        }
    }

    private func saveEdits() {
        isSaving = true; errorMessage = nil
        let t = transcript; let c = selectedCategory
        let td = todos.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let loc = selectedLocation
        Task {
            do {
                locationService.removeGeofence(noteID: note.id)
                try await viewModel.updateNote(note, transcript: t, category: c, todos: td, location: loc)
                if let loc {
                    let dto = NoteDTO(id: note.id, transcript: t, createdAt: note.safeCreatedAt,
                                     category: c.rawValue,
                                     latitude: loc.coordinate.latitude,
                                     longitude: loc.coordinate.longitude,
                                     locationName: loc.name, todos: td)
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
