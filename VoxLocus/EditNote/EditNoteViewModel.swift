import SwiftUI
import Combine
import CoreLocation
internal import CoreData

/// Owns all state and business logic for the edit-note form: seeding
/// editable fields from the note being edited, NLP to-do re-extraction,
/// category suggestion, and persisting edits (via `NotesListViewModel`) plus
/// the associated geofence update. `EditNoteView` only binds to this and
/// renders.
@MainActor
final class EditNoteViewModel: ObservableObject {
    @Published var transcript: String
    @Published var selectedCategory: NoteCategory
    @Published var todos: [TodoItem]
    @Published var selectedLocation: LocationResult?
    @Published var isExtracting = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let note: NoteEntity
    private let notesListViewModel: NotesListViewModel
    private var locationService: LocationGeofenceService?

    init(note: NoteEntity, notesListViewModel: NotesListViewModel) {
        self.note = note
        self.notesListViewModel = notesListViewModel
        _transcript       = Published(initialValue: note.safeTranscript)
        _selectedCategory = Published(initialValue: NoteCategory(rawValue: note.safeCategory) ?? .other)
        _todos            = Published(initialValue: note.safeTodos)
        if note.isAccessible, note.latitude != 0 || note.longitude != 0,
           let name = note.locationName, !name.isEmpty {
            _selectedLocation = Published(initialValue: LocationResult(
                name: name, subtitle: "",
                coordinate: CLLocationCoordinate2D(latitude: note.latitude, longitude: note.longitude)
            ))
        } else {
            _selectedLocation = Published(initialValue: nil)
        }
    }

    var isSaveDisabled: Bool {
        isSaving || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAutoSuggestDisabled: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Swaps in the app's shared LocationGeofenceService (injected via
    /// @EnvironmentObject, which isn't available inside View.init()).
    func attach(locationService: LocationGeofenceService) {
        self.locationService = locationService
    }

    func applySuggestedCategory() {
        selectedCategory = NLPTodoExtractor.suggestCategory(for: transcript)
    }

    func addEmptyTodo() {
        todos.append(TodoItem(text: ""))
    }

    func deleteTodos(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
    }

    func moveTodos(from source: IndexSet, to destination: Int) {
        todos.move(fromOffsets: source, toOffset: destination)
    }

    func reExtractTodos() {
        isExtracting = true
        Task {
            let extracted = await NLPTodoExtractor.extractTodos(from: transcript)
            let existing  = Set(todos.map { $0.text.lowercased() })
            todos.append(contentsOf: extracted.filter { !existing.contains($0.text.lowercased()) })
            isExtracting = false
        }
    }

    func save(onSaved: @escaping () -> Void) {
        isSaving = true; errorMessage = nil
        let t = transcript; let c = selectedCategory
        let td = todos.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let loc = selectedLocation
        let rawTitle = t.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?.trimmingCharacters(in: .whitespaces) ?? ""
        let newTitle = rawTitle.isEmpty
            ? (note.title ?? String(localized: "Note \(Date().formatted(date: .abbreviated, time: .shortened))"))
            : String(rawTitle.prefix(60))
        Task {
            do {
                locationService?.removeGeofence(noteID: note.id)
                try await notesListViewModel.saveEdits(note: note, newTitle: newTitle, newTranscript: t,
                                                        newCategory: c.rawValue, newTodos: td)
                if let loc {
                    let dto = NoteDTO(id: note.id, title: note.title!, transcript: t,
                                       createdAt: note.safeCreatedAt, updatedAt: note.updatedAt,
                                       category: c.rawValue,
                                       latitude: loc.coordinate.latitude,
                                       longitude: loc.coordinate.longitude,
                                       locationName: loc.name, todos: td)
                    locationService?.registerGeofence(for: dto)
                }
                await MainActor.run { self.isSaving = false; onSaved() }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = String(localized: "Save failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
