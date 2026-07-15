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
        Self.applyRoundedChrome()
        return true
    }

    /// `.fontDesign(.rounded)` (set on the SwiftUI root) only reaches
    /// ordinary `Text`/`Label` views — navigation titles and tab bar item
    /// labels are drawn by UIKit and never see that environment value, so
    /// they'd keep rendering in the default San Francisco font without this.
    private static func applyRoundedChrome() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        UINavigationBar.appearance().titleTextAttributes = [.font: rounded(17, .semibold)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: rounded(34, .bold)]

        UITabBarItem.appearance().setTitleTextAttributes([.font: rounded(11, .medium)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: rounded(11, .semibold)], for: .selected)
    }
}

@main
struct SmartNotesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let persistenceController = PersistenceController.shared
    @StateObject private var locationService: LocationGeofenceService
    @StateObject private var networkMonitor  = NetworkMonitor.shared
    @StateObject private var authService     = AuthService.shared
    @StateObject private var rootViewModel: RootViewModel
    @State private var showIntro = true

    init() {
        let locationService = LocationGeofenceService()
        _locationService = StateObject(wrappedValue: locationService)
        _rootViewModel = StateObject(wrappedValue: RootViewModel(
            locationService: locationService, networkMonitor: NetworkMonitor.shared
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showIntro {
                    IntroView {
                        withAnimation(.easeInOut(duration: 0.35)) { showIntro = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                } else {
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
                    .transition(.opacity)
                }
            }
            .fontDesign(.rounded)
            .onAppear { rootViewModel.onLaunch() }
            .task { await rootViewModel.flushPendingSyncIfNeeded() }
            .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
                rootViewModel.networkStatusChanged(wasConnected: oldValue, isConnected: newValue)
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                rootViewModel.signInStatusChanged(isSignedIn: signedIn)
            }
        }
    }
}

