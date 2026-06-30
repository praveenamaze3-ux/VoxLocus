//
//  VoxLocusApp.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import SwiftUI
import CoreData

@main
struct VoxLocusApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
