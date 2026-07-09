import FirebaseFirestore
import FirebaseAuth
import Foundation

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

    func flush() async {
        guard !pending.isEmpty else { return }
        let items = pending; pending.removeAll()
        for dto in items {
            do { try await FirebaseSyncService.shared.uploadNote(dto) }
            catch { pending.append(dto) }
        }
    }
}
