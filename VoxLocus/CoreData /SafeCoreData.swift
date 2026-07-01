//
//  SafeCoreData.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//
//
//  SafeCoreData.swift
//  SmartNotes
//
//  Single source of truth for safe Core Data access.
//  Import this pattern everywhere instead of guarding in each view.
//
//  HOW EXC_BAD_INSTRUCTION HAPPENS:
//  Core Data uses lazy "faulting" — when an object is deleted or its
//  context is reset, the NSManagedObject shell stays in memory but its
//  data is wiped. Any property access on that shell traps with
//  EXC_BAD_INSTRUCTION because Swift declared the property non-optional
//  but the underlying ObjC layer returns nil.
//
//  THE FIX: Never access a managed object property without first
//  checking isFault + isDeleted + managedObjectContext != nil.
//  This file centralises that check so you can't forget it.
//
internal import CoreData
import SwiftUI

// MARK: - NSManagedObject safe-access helpers

extension NSManagedObject {

    /// True if this object is safe to read properties from.
    /// Always check this before accessing ANY property on a Core Data entity.
    var isAccessible: Bool {
        !isDeleted
            && !isFault
            && managedObjectContext != nil
    }
}

// MARK: - NoteEntity specific safe accessors

extension NoteEntity {

    var safeTranscript:   String      { isAccessible ? (transcript ?? "") : "" }
    var safeCategory:     String      { isAccessible ? (category ?? "") : "" }
    var safeLocationName: String?     { isAccessible ? locationName : nil }
    var safeCreatedAt:    Date        { isAccessible ? createdAt : Date() }
    var safeTodos:        [TodoItem]  { isAccessible ? todos : [] }
    var safeIsSynced:     Bool        { isAccessible ? isSyncedToCloud : false }
    var safeLatitude:     Double      { isAccessible ? latitude : 0 }
    var safeLongitude:    Double      { isAccessible ? longitude : 0 }
}

// MARK: - SwiftUI ViewModifier: auto-dismiss when object is deleted

/// Attach to any view that displays a single Core Data object.
/// Automatically dismisses when the object is deleted/invalidated.
struct SafeManagedObjectModifier: ViewModifier {
    @ObservedObject var object: NSManagedObject
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onChange(of: object.isDeleted) { _, deleted in
                if deleted { dismiss() }
            }
            .onChange(of: object.managedObjectContext == nil) { _, contextGone in
                if contextGone { dismiss() }
            }
    }
}

extension View {
    /// Attach to any detail/edit view that displays one Core Data entity.
    /// Dismisses automatically if the entity is deleted from underneath it.
    func dismissWhenDeleted(_ object: NSManagedObject) -> some View {
        modifier(SafeManagedObjectModifier(object: object))
    }
}

// MARK: - Safe perform on NSManagedObjectContext

extension NSManagedObjectContext {

    /// Performs a throwing block on this context and saves if changes exist.
    /// Wraps the common pattern of perform + save into one call.
    func performAndSave(_ block: @escaping () throws -> Void) async throws {
        try await perform {
            try block()
            if self.hasChanges {
                try self.save()
            }
        }
    }
}
