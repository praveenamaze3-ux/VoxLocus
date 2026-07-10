
internal import CoreData

final class PersistenceController {

    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        let sample = NoteEntity(context: ctx)
        sample.id            = UUID()
        sample.title         = "Buy milk and call the dentist"
        sample.transcript    = "Buy milk and call the dentist tomorrow morning."
        sample.createdAt     = Date()
        sample.updatedAt     = Date()
        sample.category      = "Personal"
        sample.latitude      = 37.3349
        sample.longitude     = -122.0090
        sample.locationName  = "Apple Park"
        sample.isSoftDeleted = false
        sample.isSyncedToCloud = false
        try? ctx.save()
        return controller
    }()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "SmartNotes",
            managedObjectModel: Self.makeManagedObjectModel()
        )
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

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    func saveContext(_ context: NSManagedObjectContext? = nil) {
        let ctx = context ?? container.viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch { print("⚠️ Core Data save error: \(error)") }
    }

    // MARK: - Programmatic model

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let note  = NSEntityDescription()
        note.name = "NoteEntity"
        note.managedObjectClassName = NSStringFromClass(NoteEntity.self)

        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = true,
                  renamedFrom: String? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = optional
            a.renamingIdentifier = renamedFrom
            return a
        }

        note.properties = [
            attr("id",               .UUIDAttributeType,    optional: false),
            attr("title",            .stringAttributeType),           // NEW
            attr("transcript",       .stringAttributeType),
            attr("encryptedPayload", .binaryDataAttributeType),
            attr("createdAt",        .dateAttributeType,    optional: false),
            attr("updatedAt",        .dateAttributeType,    optional: false), // NEW
            attr("category",         .stringAttributeType),
            attr("latitude",         .doubleAttributeType),
            attr("longitude",        .doubleAttributeType),
            attr("locationName",     .stringAttributeType),
            attr("isSyncedToCloud",  .booleanAttributeType, optional: false),
            // Renamed from "isDeleted": that name collides with NSManagedObject's
            // own transient `isDeleted` property and crashes on assignment
            // (Objective-C's `is`-prefix convention maps its setter to
            // `setDeleted:`, which Core Data never synthesizes for the override).
            attr("isSoftDeleted",    .booleanAttributeType, optional: false, renamedFrom: "isDeleted"),
            attr("todosJSON",        .stringAttributeType),
            attr("ownerUID",         .stringAttributeType),           // NEW: scopes notes to the signed-in account
        ]
        model.entities = [note]
        return model
    }
}

