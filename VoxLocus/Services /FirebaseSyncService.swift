//
//  FirebaseSyncService.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

//
//  FirebaseSyncService.swift
//  SmartNotes
//
//  Pushes encrypted note payloads to Cloud Firestore. The plaintext
//  transcript/todos never leave the device — only the AES-GCM sealed blob
//  produced by EncryptionService is uploaded.
//
//  Requires: Firebase SDK (FirebaseFirestore) added via SPM, and a
//  GoogleService-Info.plist added to the Xcode target.
//

import FirebaseFirestore
import FirebaseAuth
import Foundation
internal import CoreData

actor FirebaseSyncService {

    static let shared = FirebaseSyncService()
    private let db = Firestore.firestore()

    /// Ensures we have an (anonymous, by default) authenticated user so
    /// Firestore security rules can scope documents per-user.
    private func ensureSignedIn() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// Uploads one note's encrypted payload. Safe to call repeatedly —
    /// uses `setData(merge:)` so re-syncs overwrite rather than duplicate.
    func uploadEncryptedNote(id: UUID, encryptedPayload: Data, category: String, createdAt: Date) async throws {
        let uid = try await ensureSignedIn()

        let doc: [String: Any] = [
            "id": id.uuidString,
            "payload": encryptedPayload.base64EncodedString(),
            "category": category,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: Date())
        ]

        try await db.collection("users")
            .document(uid)
            .collection("notes")
            .document(id.uuidString)
            .setData(doc, merge: true)
    }

    func deleteNote(id: UUID) async throws {
        let uid = try await ensureSignedIn()
        try await db.collection("users")
            .document(uid)
            .collection("notes")
            .document(id.uuidString)
            .delete()
    }

    /// Fetches and decrypts all of the signed-in user's notes (e.g. for a
    /// fresh-install restore flow).
    func fetchAllNotes() async throws -> [NoteDTO] {
        let uid = try await ensureSignedIn()
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("notes")
            .getDocuments()

        return snapshot.documents.compactMap { doc -> NoteDTO? in
            guard
                let base64 = doc.data()["payload"] as? String,
                let data = Data(base64Encoded: base64)
            else { return nil }
            return try? EncryptionService.decrypt(data, as: NoteDTO.self)
        }
    }
}

/// Lightweight retry queue so uploads survive transient connectivity loss.
/// NotesListViewModel calls `enqueue` whenever a save happens offline;
/// NetworkMonitor's connectivity callback triggers `flush()`.
actor SyncRetryQueue {
    static let shared = SyncRetryQueue()
    private var pending: [(UUID, Data, String, Date)] = []

    func enqueue(id: UUID, payload: Data, category: String, createdAt: Date) {
        pending.append((id, payload, category, createdAt))
    }

    func flush() async {
        guard !pending.isEmpty else { return }
        let items = pending
        pending.removeAll()
        for (id, payload, category, createdAt) in items {
            do {
                try await FirebaseSyncService.shared.uploadEncryptedNote(
                    id: id, encryptedPayload: payload, category: category, createdAt: createdAt
                )
                // Mark synced in Core Data so the UI updates.
                let bgContext = PersistenceController.shared.newBackgroundContext()
                await bgContext.perform {
                    let request = NoteEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                    if let entity = try? bgContext.fetch(request).first {
                        entity.isSyncedToCloud = true
                        try? bgContext.save()
                    }
                }
            } catch {
                print("⚠️ Retry sync failed for \(id): \(error.localizedDescription)")
                // Re-queue for the next connectivity event.
                pending.append((id, payload, category, createdAt))
            }
        }
    }
}
