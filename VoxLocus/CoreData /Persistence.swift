//
//  Persistence.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

//
//  PersistenceController.swift
//  SmartNotes
//
//  Core Data stack built programmatically (NSManagedObjectModel) so the whole
//  project can live in plain .swift files. If you prefer, you can instead
//  create a SmartNotes.xcdatamodeld in Xcode's model editor with the same
//  entity/attributes shown below and delete `makeManagedObjectModel()`.
//

internal import CoreData

final class PersistenceController {

    static let shared = PersistenceController()

    /// In-memory controller for SwiftUI previews / unit tests.
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        let sample = NoteEntity(context: ctx)
        sample.id = UUID()
        sample.transcript = "Buy milk and call the dentist tomorrow morning."
        sample.createdAt = Date()
        sample.category = "Personal"
        sample.latitude = 37.3349
        sample.longitude = -122.0090
        sample.locationName = "Apple Park"
        try? ctx.save()
        return controller
    }()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SmartNotes", managedObjectModel: Self.makeManagedObjectModel())

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Returns a new background context for write-heavy / off-main-thread work.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    func saveContext(_ context: NSManagedObjectContext? = nil) {
        let ctx = context ?? container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("⚠️ Core Data save error: \(error)")
        }
    }

    /// On launch, finds every note that never made it to Firebase and
    /// pushes it back into the retry queue so it syncs as soon as possible.
    func requeuePendingNotes() async {
        let context = container.viewContext
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isSyncedToCloud == NO")

        guard let pending = try? context.fetch(request), !pending.isEmpty else { return }
        print("ℹ️ Re-queuing \(pending.count) unsynced note(s)…")

        for note in pending {
            guard let payload = note.encryptedPayload else { continue }
            await SyncRetryQueue.shared.enqueue(
                id: note.id,
                payload: payload,
                category: note.category ?? "Other",
                createdAt: note.createdAt
            )
        }
        await SyncRetryQueue.shared.flush()
    }

    // MARK: - Programmatic model

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let note = NSEntityDescription()
        note.name = "NoteEntity"
        note.managedObjectClassName = NSStringFromClass(NoteEntity.self)

        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = true) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            return a
        }

        note.properties = [
            attr("id", .UUIDAttributeType, optional: false),
            attr("transcript", .stringAttributeType),
            attr("encryptedPayload", .binaryDataAttributeType),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("category", .stringAttributeType),
            attr("latitude", .doubleAttributeType),
            attr("longitude", .doubleAttributeType),
            attr("locationName", .stringAttributeType),
            attr("isSyncedToCloud", .booleanAttributeType, optional: false),
            attr("todosJSON", .stringAttributeType)
        ]

        model.entities = [note]
        return model
    }
}
