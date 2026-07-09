import SwiftUI
import UIKit
import FirebaseCore
internal import CoreData

/// Configures Firebase before any SwiftUI state (e.g. `AuthService.shared`,
/// which calls `Auth.auth()` on init) gets a chance to touch it.
/// `App`'s stored-property defaults are evaluated before `init()`'s body
/// runs, so configuring Firebase in `App.init()` is too late once any
/// property default depends on it — `didFinishLaunching` is guaranteed by
/// UIKit to run first.
final class AppDelegate: NSObject, UIApplicationDelegate {          // make sure the the firebase is configured first before any other process starts .
    func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct SmartNotesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let persistenceController = PersistenceController.shared
    @StateObject private var locationService = LocationGeofenceService()
    @StateObject private var networkMonitor  = NetworkMonitor.shared
    @StateObject private var authService     = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isSignedIn {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(locationService)
                        .environmentObject(networkMonitor)
                        .environmentObject(authService)
                } else {
                    AuthView(authService: authService)
                }
            }
            .onAppear {
                // Request at launch so the system dialog shows immediately
                // on first run, before any view tries to use location.
                locationService.requestPermission()
            }
        }
    }
}

