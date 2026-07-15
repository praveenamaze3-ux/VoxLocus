import Foundation
import Combine
import CoreLocation
internal import CoreData
import FirebaseAuth

/// Owns all state and business logic for the new-note form: NLP category
/// suggestion, NLP to-do extraction, Reminders sync, CoreData persistence,
/// geofence registration, and Firebase sync. `AddNoteView` only binds to
/// this and renders.
@MainActor
final class AddNoteViewModel: ObservableObject {
    @Published var transcript: String = "" {
        didSet {
            guard transcript != oldValue, !transcript.isEmpty else { return }
            selectedCategory = NLPTodoExtractor.suggestCategory(for: transcript)
        }
    }
    @Published var selectedCategory: NoteCategory = .other
    @Published var selectedLocation: LocationResult? = nil
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var locationService: LocationGeofenceService?

    var isSaveDisabled: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
    }

    /// Swaps in the app's shared LocationGeofenceService (injected via
    /// @EnvironmentObject, which isn't available inside View.init()).
    func attach(locationService: LocationGeofenceService) {
        self.locationService = locationService
    }

    func save(onSaved: @escaping () -> Void) {
        isSaving = true; errorMessage = nil
        let text = transcript; let category = selectedCategory; let location = selectedLocation
        Task {
            do {
                let todos = await NLPTodoExtractor.extractTodos(from: text)
                var finalTodos = todos
                if !todos.isEmpty {
                    do {
                        finalTodos = try await RemindersService.shared.createChecklist(
                            for: todos, noteTitle: String(text.prefix(40)))
                    } catch {
                        let isXPC = error.localizedDescription.contains("XPC") ||
                                    error.localizedDescription.contains("calaccesssd")
                        if !isXPC { print("Reminders: \(error)") }
                    }
                }
                let rawTitle = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                    .first?.trimmingCharacters(in: .whitespaces) ?? ""
                let title = rawTitle.isEmpty
                    ? String(localized: "Note \(Date().formatted(date: .abbreviated, time: .shortened))")
                    : String(rawTitle.prefix(60))

                let now = Date()
                let dto = NoteDTO(id: UUID(), title: title, transcript: text, createdAt: now, updatedAt: now,
                                   category: category.rawValue,
                                   latitude: location?.coordinate.latitude ?? 0,
                                   longitude: location?.coordinate.longitude ?? 0,
                                   locationName: location?.name, todos: finalTodos)
                try await Self.saveToCoreData(dto)
                if location != nil { locationService?.registerGeofence(for: dto) }
                await Self.syncToFirebase(dto)
                await MainActor.run { self.isSaving = false; onSaved() }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = String(localized: "Failed to save: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func saveToCoreData(_ dto: NoteDTO) async throws {
        let ctx = PersistenceController.shared.newBackgroundContext()
        try await ctx.performAndSave {
            let e = NoteEntity(context: ctx)
            e.id = dto.id; e.title = dto.title; e.transcript = dto.transcript; e.createdAt = dto.createdAt
            e.updatedAt = dto.updatedAt
            e.category = dto.category; e.latitude = dto.latitude; e.longitude = dto.longitude
            e.locationName = dto.locationName; e.todos = dto.todos
            e.isSyncedToCloud = false; e.isSoftDeleted = false
            e.ownerUID = Auth.auth().currentUser?.uid
            e.encryptedPayload = try? EncryptionService.encrypt(dto)
        }
    }

    private static func syncToFirebase(_ dto: NoteDTO) async {
        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadNote(dto)
                let ctx = PersistenceController.shared.newBackgroundContext()
                await ctx.perform {
                    let req = NoteEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                    if let e = try? ctx.fetch(req).first { e.isSyncedToCloud = true; try? ctx.save() }
                }
            } catch {
                await SyncRetryQueue.shared.enqueue(dto)
            }
        } else {
            await SyncRetryQueue.shared.enqueue(dto)
        }
    }
}
