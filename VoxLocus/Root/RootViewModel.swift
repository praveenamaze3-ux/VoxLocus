import Foundation
import Combine

/// Owns the app-launch orchestration that previously lived directly in
/// `SmartNotesApp.body`'s `onAppear`/`task`/`onChange` modifiers: requesting
/// location permission at launch, and flushing the offline sync queue
/// whenever connectivity or sign-in state changes in a way that makes a
/// flush worthwhile.
@MainActor
final class RootViewModel: ObservableObject {
    private let locationService: LocationGeofenceService
    private let networkMonitor: NetworkMonitor

    init(locationService: LocationGeofenceService, networkMonitor: NetworkMonitor) {
        self.locationService = locationService
        self.networkMonitor = networkMonitor
    }

    /// Request at launch so the system dialog shows immediately on first
    /// run, before any view tries to use location.
    func onLaunch() {
        locationService.requestPermission()
    }

    /// Catches notes that were created offline in a previous session and
    /// never got flushed before the app closed.
    func flushPendingSyncIfNeeded() async {
        if networkMonitor.isConnected {
            await SyncRetryQueue.shared.flush()
        }
    }

    /// The moment connectivity comes back, retry every pending-sync note so
    /// it flips from "Pending sync" to "Synced & encrypted in cloud" without
    /// the user doing anything.
    func networkStatusChanged(wasConnected: Bool, isConnected: Bool) {
        guard isConnected && !wasConnected else { return }
        Task { await SyncRetryQueue.shared.flush() }
    }

    func signInStatusChanged(isSignedIn: Bool) {
        guard isSignedIn && networkMonitor.isConnected else { return }
        Task { await SyncRetryQueue.shared.flush() }
    }
}
