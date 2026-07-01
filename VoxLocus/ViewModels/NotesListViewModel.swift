//
//  NotesListViewModel.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//
//  NotesListViewModel.swift
//  SmartNotes
//
//
//  NotesListViewModel.swift
//  SmartNotes
//

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

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
         locationService: LocationGeofenceService) {
        self.context = context
        self.locationService = locationService
        super.init()
        configureFetchedResultsController()
    }

    private func configureFetchedResultsController() {
        let request = NoteEntity.fetchRequest()
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
        } catch {
            print("⚠️ Fetch error: \(error)")
        }
    }

    /// Combines text search, category filter, "has todos" filter, and
    /// proximity-based geofence suggestions.
    var filteredNotes: [NoteEntity] {
        notes.filter { note in
            // Guard against faulted/deleted objects reaching the list rows.
            guard !note.isDeleted, note.managedObjectContext != nil else { return false }
            let matchesCategory = selectedCategory == nil || note.category == selectedCategory?.rawValue
            let matchesSearch = searchText.isEmpty ||
                (note.transcript?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesTodos = !showOnlyWithTodos || !note.todos.isEmpty
            let matchesNearby = !showOnlyNearby || locationService.suggestedNoteIDs.contains(note.id)
            return matchesCategory && matchesSearch && matchesTodos && matchesNearby
        }
    }

    /// Notes the user is currently geofenced-near — surfaced as a banner.
    var nearbySuggestions: [NoteEntity] {
        notes.filter { locationService.suggestedNoteIDs.contains($0.id) }
    }

    func delete(_ note: NoteEntity) {
        let id = note.id
        locationService.removeGeofence(noteID: id)
        context.delete(note)
        PersistenceController.shared.saveContext(context)

        Task {
            try? await FirebaseSyncService.shared.deleteNote(id: id)
        }
    }

    /// Updates an existing note's transcript, category, and todos, then
    /// re-encrypts and re-syncs to Firebase.
    func updateNote(
        _ note: NoteEntity,
        transcript: String,
        category: NoteCategory,
        todos: [TodoItem],
        location: LocationResult? = nil
    ) async throws {
        guard !note.isDeleted, note.managedObjectContext != nil else { return }

        // Update on a background context to keep the main thread free.
        let bgContext = PersistenceController.shared.newBackgroundContext()
        let noteID = note.id

        try await bgContext.perform {
            let request = NoteEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
            guard let entity = try bgContext.fetch(request).first else { return }

            entity.transcript     = transcript
            entity.category       = category.rawValue
            entity.todos          = todos
            entity.isSyncedToCloud = false  // will flip to true after successful upload

            // Build an updated DTO for re-encryption.
            let dto = NoteDTO(
                id: noteID,
                transcript: transcript,
                createdAt: entity.createdAt,
                category: category.rawValue,
                latitude: entity.latitude,
                longitude: entity.longitude,
                locationName: entity.locationName,
                todos: todos
            )
            entity.encryptedPayload = try? EncryptionService.encrypt(dto)

            try bgContext.save()
        }

        // Re-sync the updated encrypted payload to Firebase.
        await syncUpdateToFirebase(noteID: noteID, transcript: transcript,
                                   category: category, todos: todos)
    }

    private func syncUpdateToFirebase(
        noteID: UUID,
        transcript: String,
        category: NoteCategory,
        todos: [TodoItem]
    ) async {
        // We need the entity's full data for the DTO — fetch from view context.
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }

        let dto = NoteDTO(
            id: noteID,
            transcript: transcript,
            createdAt: entity.createdAt,
            category: category.rawValue,
            latitude: entity.latitude,
            longitude: entity.longitude,
            locationName: entity.locationName,
            todos: todos
        )

        guard let payload = try? EncryptionService.encrypt(dto) else { return }

        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadEncryptedNote(
                    id: noteID, encryptedPayload: payload,
                    category: category.rawValue, createdAt: dto.createdAt
                )
                // Mark as synced in Core Data.
                let bgContext = PersistenceController.shared.newBackgroundContext()
                await bgContext.perform {
                    let req = NoteEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
                    if let e = try? bgContext.fetch(req).first {
                        e.isSyncedToCloud = true
                        try? bgContext.save()
                    }
                }
            } catch {
                await SyncRetryQueue.shared.enqueue(
                    id: noteID, payload: payload,
                    category: category.rawValue, createdAt: dto.createdAt
                )
            }
        } else {
            await SyncRetryQueue.shared.enqueue(
                id: noteID, payload: payload,
                category: category.rawValue, createdAt: dto.createdAt
            )
        }
    }

    func decryptedDTO(for note: NoteEntity) -> NoteDTO? {
        guard let payload = note.encryptedPayload else { return nil }
        return try? EncryptionService.decrypt(payload, as: NoteDTO.self)
    }
}

extension NotesListViewModel: NSFetchedResultsControllerDelegate {
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            self.notes = self.fetchedResultsController.fetchedObjects ?? []
        }
    }
}
