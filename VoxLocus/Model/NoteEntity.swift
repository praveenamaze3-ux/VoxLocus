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
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var todosJSON: String?
    /// Firebase Auth uid of the account that created this note. Scopes the
    /// local (single shared SQLite store) so signing in as a different
    /// account never shows another account's notes.
    @NSManaged public var ownerUID: String?
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
        return first.isEmpty ? String(localized: "Untitled Note") : String(first.prefix(60))
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

    /// Localized display name. `rawValue` stays a fixed, English identifier
    /// since it's persisted (CoreData/Firebase) and used for filter matching —
    /// only this computed property is shown to the user, so it's the only
    /// piece that needs to flow through the String Catalog.
    var displayName: String {
        switch self {
        case .personal: return String(localized: "Personal", comment: "Note category")
        case .work:     return String(localized: "Work", comment: "Note category")
        case .shopping: return String(localized: "Shopping", comment: "Note category")
        case .health:   return String(localized: "Health", comment: "Note category")
        case .ideas:    return String(localized: "Ideas", comment: "Note category")
        case .other:    return String(localized: "Other", comment: "Note category")
        }
    }

    /// Localized display name for an arbitrary persisted category string —
    /// falls back to the raw value itself if it doesn't match a known case
    /// (e.g. legacy data), so it always renders something reasonable.
    static func displayName(for rawValue: String) -> String {
        NoteCategory(rawValue: rawValue)?.displayName ?? rawValue
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
