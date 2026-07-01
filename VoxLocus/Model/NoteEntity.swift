//
//  NoteEntity.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

internal import CoreData
import Foundation

@objc(NoteEntity)
class NoteEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var transcript: String?
    @NSManaged public var encryptedPayload: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var category: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var locationName: String?
    @NSManaged public var isSyncedToCloud: Bool
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
}

struct TodoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var isCompleted: Bool = false
    var reminderIdentifier: String?
}

enum NoteCategory: String, CaseIterable, Identifiable, Codable {
    case personal = "Personal"
    case work = "Work"
    case shopping = "Shopping"
    case health = "Health"
    case ideas = "Ideas"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .work: return "briefcase.fill"
        case .shopping: return "cart.fill"
        case .health: return "heart.fill"
        case .ideas: return "lightbulb.fill"
        case .other: return "tray.fill"
        }
    }
}

struct NoteDTO: Codable, Identifiable, Sendable {
    let id: UUID
    var transcript: String
    var createdAt: Date
    var category: String
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var todos: [TodoItem]
}
