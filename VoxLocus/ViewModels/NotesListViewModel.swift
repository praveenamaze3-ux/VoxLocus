import Foundation
internal import CoreData
import Combine

@MainActor
final class NotesListViewModel: NSObject, ObservableObject {

    @Published private(set) var notes: [NoteEntity] = []
    @Published var selectedCategory: NoteCategory? = nil
    @Published var searchText: String = ""
    @Published var showOnlyWithTodos: Bool = false
    @Published var showOnlyNearby: Bool = false

    private var fetchedResultsController: NSFetchedResultsController<NoteEntity>!
    private let context: NSManagedObjectContext
    private let locationService: LocationGeofenceService
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
         locationService: LocationGeofenceService) {
        self.context = context
        self.locationService = locationService
        super.init()
        configureFetchedResultsController()
        observeLocationSuggestions()
    }

    // MARK: - FRC

    private func configureFetchedResultsController() {
        let request = NoteEntity.fetchRequest()
        // Exclude soft-deleted notes.
        request.predicate = NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \NoteEntity.createdAt, ascending: false)]

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            notes = fetchedResultsController.fetchedObjects ?? []
        } catch { print("⚠️ Fetch error: \(error)") }
    }

    private func observeLocationSuggestions() {
        locationService.$suggestedNoteIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Safe managed object access

    /// Returns note.id only if the object is still alive in its context.
    /// Prevents EXC_BAD_INSTRUCTION when a note is mid-deletion.
    private func safeID(for note: NoteEntity) -> UUID? {
        guard note.managedObjectContext != nil, !note.isSoftDeleted else { return nil }
        return note.id
    }

    // MARK: - Filtering (all original filters preserved)

    var filteredNotes: [NoteEntity] {
        notes.filter { note in
            guard note.managedObjectContext != nil, !note.isSoftDeleted else { return false }
            let matchesCategory = selectedCategory == nil || note.category == selectedCategory?.rawValue
            let matchesSearch   = searchText.isEmpty ||
                (note.transcript?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (note.title?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesTodos  = !showOnlyWithTodos || !note.todos.isEmpty
            let matchesNearby: Bool = {
                guard showOnlyNearby else { return true }
                guard let id = safeID(for: note) else { return false }
                return locationService.suggestedNoteIDs.contains(id)
            }()
            return matchesCategory && matchesSearch && matchesTodos && matchesNearby
        }
    }

    /// Notes geofenced-near the user — shown in the banner.
    var nearbySuggestions: [NoteEntity] {
        notes.compactMap { note -> NoteEntity? in
            guard let id = safeID(for: note) else { return nil }
            return locationService.suggestedNoteIDs.contains(id) ? note : nil
        }
    }

    // MARK: - Delete (soft)

    func delete(_ note: NoteEntity) {
        // Snapshot UUID BEFORE any mutation — entity may fault after saveContext.
        let id = note.id
        locationService.removeGeofence(noteID: id)

        note.isSoftDeleted   = true
        note.updatedAt       = Date()
        note.isSyncedToCloud = false
        PersistenceController.shared.saveContext(context)
        // Never reference `note` below this line — use `id` only.

        Task { try? await FirebaseSyncService.shared.deleteNote(id: id) }
    }

    // MARK: - Edit persistence

    /// Saves title/transcript/category/todos changes to CoreData and re-syncs to Firestore.
    func saveEdits(note: NoteEntity, newTitle: String, newTranscript: String,
                   newCategory: String, newTodos: [TodoItem]) async throws {
        note.title           = newTitle
        note.transcript      = newTranscript
        note.category        = newCategory
        note.todos           = newTodos
        note.updatedAt       = Date()
        note.isSyncedToCloud = false
        PersistenceController.shared.saveContext(context)

        guard let dto = buildDTO(from: note) else { return }
        Task {
            if NetworkMonitor.shared.isConnected {
                try? await FirebaseSyncService.shared.uploadNote(dto)
                await markSynced(id: dto.id)
            } else {
                await SyncRetryQueue.shared.enqueue(dto)
            }
        }
    }

    // MARK: - Decryption (original feature)

    func decryptedDTO(for note: NoteEntity) -> NoteDTO? {
        guard let payload = note.encryptedPayload else { return nil }
        return try? EncryptionService.decrypt(payload, as: NoteDTO.self)
    }

    // MARK: - Helpers

    private func buildDTO(from note: NoteEntity) -> NoteDTO? {
        guard note.managedObjectContext != nil else { return nil }
        return NoteDTO(
            id:           note.id,
            title:        note.displayTitle,
            transcript:   note.transcript ?? "",
            createdAt:    note.createdAt,
            updatedAt:    note.updatedAt,
            category:     note.category ?? "Other",
            latitude:     note.latitude,
            longitude:    note.longitude,
            locationName: note.locationName,
            todos:        note.todos
        )
    }

    private func markSynced(id: UUID) async {
        let bg = PersistenceController.shared.newBackgroundContext()
        try? await bg.perform {
            let req = NoteEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let e = try bg.fetch(req).first { e.isSyncedToCloud = true; try bg.save() }
        }
    }
}

extension NotesListViewModel: NSFetchedResultsControllerDelegate {
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.notes = self.fetchedResultsController.fetchedObjects ?? []
        }
    }
}

