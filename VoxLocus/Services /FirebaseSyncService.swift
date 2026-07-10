import FirebaseFirestore
import FirebaseAuth
import Foundation
internal import CoreData

actor FirebaseSyncService {

    static let shared = FirebaseSyncService()
    private let db = Firestore.firestore()

    // MARK: - Auth guard

    private func requireSignedInUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SyncError.notAuthenticated
        }
        return uid
    }

    func uploadNote(_ dto: NoteDTO) async throws {
        let uid = try requireSignedInUID()
        let doc: [String: Any] = [
            "id":               dto.id.uuidString,
            "title":            dto.title,
            "category":         dto.category,
            "locationName":     dto.locationName ?? "",
            "latitude":         dto.latitude,
            "longitude":        dto.longitude,
            "createdAt":        Timestamp(date: dto.createdAt),
            "updatedAt":        Timestamp(date: dto.updatedAt),
            "isDeleted":        false,
            "encryptedPayload": (try? EncryptionService.encrypt(dto))?.base64EncodedString() ?? ""
        ]
        try await db
            .collection("users").document(uid)
            .collection("notes").document(dto.id.uuidString)
            .setData(doc, merge: true)
    }

    func deleteNote(id: UUID) async throws {
        let uid = try requireSignedInUID()
        try await db
            .collection("users").document(uid)
            .collection("notes").document(id.uuidString)
            .updateData([
                "isDeleted": true,
                "updatedAt": Timestamp(date: Date())
            ])
    }

    // MARK: - Fetch (restore)

    func fetchAllNotes() async throws -> [NoteDTO] {
        let uid = try requireSignedInUID()
        let snapshot = try await db
            .collection("users").document(uid)
            .collection("notes")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> NoteDTO? in
            guard let base64 = doc.data()["encryptedPayload"] as? String,
                  let data = Data(base64Encoded: base64)
            else { return nil }
            return try? EncryptionService.decrypt(data, as: NoteDTO.self)
        }
    }

    enum SyncError: LocalizedError {
        case notAuthenticated
        var errorDescription: String? { "Sign in to sync notes." }
    }
}

// MARK: - Retry Queue

actor SyncRetryQueue {
    static let shared = SyncRetryQueue()
    private var pending: [NoteDTO] = []

    func enqueue(_ dto: NoteDTO) {
        pending.removeAll { $0.id == dto.id }
        pending.append(dto)
    }

    /// Re-uploads every note still marked pending-sync for the signed-in
    /// account. Reads Core Data directly — the ground truth of what's
    /// actually unsynced — rather than only the in-memory `pending` list, so
    /// notes created offline still catch up after the app is relaunched, not
    /// just within the same process. Called whenever connectivity is
    /// restored (or the app opens while already online).
    func flush() async {
        pending.removeAll()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let context = PersistenceController.shared.newBackgroundContext()
        let unsynced: [NoteDTO] = await context.perform {
            let request = NoteEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "isSyncedToCloud == NO AND (isSoftDeleted == NO OR isSoftDeleted == nil) AND ownerUID == %@",
                uid
            )
            let notes = (try? context.fetch(request)) ?? []
            return notes.map { note in
                NoteDTO(
                    id: note.id,
                    title: note.displayTitle,
                    transcript: note.transcript ?? "",
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    category: note.category ?? "Other",
                    latitude: note.latitude,
                    longitude: note.longitude,
                    locationName: note.locationName,
                    todos: note.todos
                )
            }
        }

        for dto in unsynced {
            do {
                try await FirebaseSyncService.shared.uploadNote(dto)
                await markSynced(id: dto.id, context: context)
            } catch {
                pending.append(dto)
            }
        }
    }

    private func markSynced(id: UUID, context: NSManagedObjectContext) async {
        await context.perform {
            let request = NoteEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? context.fetch(request).first {
                entity.isSyncedToCloud = true
                try? context.save()
            }
        }
    }
}
