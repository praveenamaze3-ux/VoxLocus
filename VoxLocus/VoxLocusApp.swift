//
//  VoxLocusApp.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
import SwiftUI
import FirebaseCore
import BackgroundTasks
internal import CoreData

@main
struct SmartNotesApp: App {

    let persistenceController = PersistenceController.shared
    @StateObject private var locationService = LocationGeofenceService()
    @StateObject private var networkMonitor  = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()

        // Register BGTask identifiers — MUST happen before first runloop tick.
        // BGTaskScheduler requires early registration; doing it here in init()
        // (not in body) guarantees timing.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskID.sync,
            using: nil
        ) { task in
            BGTaskRegistry.handleSyncRefresh(task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskID.cleanup,
            using: nil
        ) { task in
            BGTaskRegistry.handleSyncRefresh(task as! BGAppRefreshTask)
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskID.cleanup,
            using: nil
        ) { task in
            BGTaskRegistry.handleCleanup(task as! BGProcessingTask)
        }

    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext,
                              persistenceController.container.viewContext)
                .environmentObject(locationService)
                .environmentObject(networkMonitor)
        }
        // scenePhase: SwiftUI-native foreground/background observation.
        .onChange(of: scenePhase) { _, phase in
            switch phase {

            case .active:
                // Flush any notes that failed to sync in a previous session.
                Task {
                    await SyncRetryQueue.shared.flush()
                }

            case .background:
                // Schedule deferred BGTasks for when system picks up the work.
                BGTaskRegistry.scheduleSyncRefresh()
                BGTaskRegistry.scheduleCleanup()

                // Re-queue unsynced notes off the main actor so we don't
                // block the foreground→background transition (SIGTERM trigger).
                Task.detached(priority: .background) {
                    await PersistenceController.shared.requeuePendingNotes()
                }

            case .inactive:
                break

            @unknown default:
                break
            }
        }
        // .backgroundTask: SwiftUI-native BGAppRefreshTask handler.
        // System wakes the app, closure runs, task ends when closure returns.
        .backgroundTask(.appRefresh(BGTaskID.sync)) {
            await SyncRetryQueue.shared.flush()
        }
    }
}
