import Foundation
import Combine
import SwiftUI

/// Owns the app-launch orchestration that previously lived directly in
/// `SmartNotesApp.body`'s `onAppear`/`task`/`onChange` modifiers: requesting
/// location permission at launch, flushing the offline sync queue whenever
/// connectivity or sign-in state changes in a way that makes a flush
/// worthwhile, and — since it already owns app-lifecycle orchestration —
/// the Face ID app-lock state driven by scene-phase transitions.
@MainActor
final class RootViewModel: ObservableObject {
    private let locationService: LocationGeofenceService
    private let networkMonitor: NetworkMonitor

    @Published private(set) var isAppLocked: Bool
    @Published private(set) var isAuthenticatingLock = false
    @Published private(set) var lockScreenError: String?

    init(locationService: LocationGeofenceService, networkMonitor: NetworkMonitor) {
        self.locationService = locationService
        self.networkMonitor = networkMonitor
        self.isAppLocked = Self.shouldRequireLock
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
        // Re-arm (or clear) the lock whenever sign-in state flips — covers
        // both "signed out from the lock screen" and "signed back in".
        isAppLocked = isSignedIn ? Self.shouldRequireLock : false
        guard isSignedIn && networkMonitor.isConnected else { return }
        Task { await SyncRetryQueue.shared.flush() }
    }

    // MARK: - App lock

    /// Only `.background` arms the lock and only `.active` while already
    /// locked re-attempts unlock — `.inactive` (Control Center, a call
    /// banner, the app-switcher glance) is deliberately ignored so it never
    /// causes a false re-lock.
    func scenePhaseChanged(to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            if Self.shouldRequireLock { isAppLocked = true }
        case .active:
            if isAppLocked { Task { await attemptUnlock() } }
        default:
            break
        }
    }

    func attemptUnlock() async {
        guard !isAuthenticatingLock else { return }
        isAuthenticatingLock = true
        lockScreenError = nil
        defer { isAuthenticatingLock = false }
        switch await BiometricAuthService.shared.unlock() {
        case .success:
            isAppLocked = false
        case .failure(let error):
            lockScreenError = BiometricAuthService.shared.friendlyMessage(for: error)
        }
    }

    /// Fails open: the lock is only enforced when the persisted toggle is on
    /// AND biometrics is currently usable on this device — a user who
    /// disables/un-enrolls biometrics after opting in is never stranded.
    private static var shouldRequireLock: Bool {
        AppLockSettings.isEnabled && BiometricAuthService.shared.isAvailable
    }
}
