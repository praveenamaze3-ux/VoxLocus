//
//  BackGroundTaskManager.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//

//
//  BackgroundTaskManager.swift
//  SmartNotes
//
//  Imports: BackgroundTasks + SwiftUI only. Zero UIKit.
//
//  Background execution strategy:
//  ┌─────────────────────────────────────────────────────────────┐
//  │  Trigger               │  Mechanism                        │
//  ├─────────────────────────────────────────────────────────────┤
//  │  App goes background   │  scenePhase .background in App    │
//  │  App comes foreground  │  scenePhase .active in App        │
//  │  System wakes app      │  .backgroundTask modifier on      │
//  │  (BGAppRefreshTask)    │   WindowGroup in SmartNotesApp    │
//  │  Deferred processing   │  BGProcessingTask via scheduler   │
//  └─────────────────────────────────────────────────────────────┘
//
//  HOW SIGTERM IS PREVENTED:
//  1. Heavy work always runs in Task.detached — never blocks main actor.
//  2. BGTasks are cancelled cleanly via expirationHandler instead of
//     being forcibly killed (which produces SIGTERM).
//  3. scenePhase changes are observed in SmartNotesApp — no UIApplication
//     notifications needed.
//
import BackgroundTasks
import SwiftUI

// MARK: - Task Identifiers

enum BGTaskID {
    /// Lightweight refresh — flushes the sync retry queue.
    static let sync    = "com.smartnotes.sync"
    /// Heavier processing — re-queues all unsynced Core Data notes.
    static let cleanup = "com.smartnotes.cleanup"
}

// MARK: - Scheduler

enum BGTaskRegistry {

    // MARK: Schedule

    /// Submit a BGAppRefreshTask request so the system wakes the app
    /// ~15 minutes after it backgrounds to flush pending syncs.
    /// Call from scenePhase .background handler in SmartNotesApp.
    static func scheduleSyncRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskID.sync)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ BGAppRefreshTask schedule failed: \(error)")
        }
    }

    /// Submit a BGProcessingTask for heavier cleanup work.
    /// Requires network; iOS picks a convenient time to run it.
    static func scheduleCleanup() {
        let request = BGProcessingTaskRequest(identifier: BGTaskID.cleanup)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ BGProcessingTask schedule failed: \(error)")
        }
    }

    // MARK: Handle (called by BGTaskScheduler when system wakes the app)

    /// Handles the BGAppRefreshTask — flushes sync queue and re-schedules.
    /// Wire this to .backgroundTask(.appRefresh(BGTaskID.sync)) in SwiftNotesApp.
    static func handleSyncRefresh(_ task: BGAppRefreshTask) {
        // Always re-schedule before doing work so the next wake is guaranteed.
        scheduleSyncRefresh()

        let work = Task.detached(priority: .background) {
            await SyncRetryQueue.shared.flush()
            task.setTaskCompleted(success: true)
        }

        // Expiry: system is reclaiming time — cancel cleanly to avoid SIGTERM.
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Handles the BGProcessingTask — re-queues all unsynced notes.
    static func handleCleanup(_ task: BGProcessingTask) {
        let work = Task.detached(priority: .background) {
            await PersistenceController.shared.requeuePendingNotes()
            await SyncRetryQueue.shared.flush()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
