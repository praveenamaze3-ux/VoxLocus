//
//  NoteEntity.swift
//  SmartNotes
//

internal import CoreData
import Foundation

@objc(NoteEntity)
class NoteEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String?
    @NSManaged public var transcript: String?
    @NSManaged public var encryptedPayload: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var category: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var locationName: String?
    @NSManaged public var isSyncedToCloud: Bool
    /// User-facing soft-delete flag. Named to avoid colliding with
    /// NSManagedObject's own `isDeleted` (a transient, framework-managed
    /// property for "removed from context") — Objective-C's `is`-prefix
    /// convention maps that property's setter to `setDeleted:`, so
    /// overriding it with a persisted attribute of the same name crashes
    /// with "unrecognized selector setDeleted:" the moment it's assigned.
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var todosJSON: String?
}

extension NoteEntity {
    static func fetchRequest() -> NSFetchRequest<NoteEntity> {
        NSFetchRequest<NoteEntity>(entityName: "NoteEntity")
    }

    var todos: [TodoItem] {
        get {
            guard let json = todosJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                todosJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    /// Display title: explicit title first, otherwise first line of transcript.
    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        let first = transcript?
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Untitled Note" : String(first.prefix(60))
    }
}

/// A single extracted action item.
struct TodoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var isCompleted: Bool = false
    var reminderIdentifier: String?
}

/// Top-level category used for filtering.
enum NoteCategory: String, CaseIterable, Identifiable, Codable {
    case personal = "Personal"
    case work     = "Work"
    case shopping = "Shopping"
    case health   = "Health"
    case ideas    = "Ideas"
    case other    = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .work:     return "briefcase.fill"
        case .shopping: return "cart.fill"
        case .health:   return "heart.fill"
        case .ideas:    return "lightbulb.fill"
        case .other:    return "tray.fill"
        }
    }
}

/// Sendable DTO used across concurrency boundaries and for Firebase.
/// Added: title, updatedAt (required by v7 FirebaseSyncService).
struct NoteDTO: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var transcript: String
    var createdAt: Date
    var updatedAt: Date
    var category: String
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var todos: [TodoItem]
}
