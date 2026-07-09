
import SwiftUI
import FirebaseAuth
internal import CoreData

struct ContentView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @EnvironmentObject var authService: AuthService
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        TabView {
            RecordingView()
                .tabItem { Label("Record", systemImage: "mic.fill") }

            NotesListView(
                viewModel: NotesListViewModel(context: context, locationService: locationService)
            )
            .tabItem { Label("Notes", systemImage: "note.text") }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .tint(AppTheme.accent)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

// MARK: - Account tab

struct AccountView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in as") {
                    Label(authService.currentUser?.email ?? "—", systemImage: "envelope")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.vertical, 4)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(AppTheme.surface.opacity(0.55)), in: RoundedRectangle(cornerRadius: 14))
                )

                Section {
                    Button(role: .destructive) { authService.signOut() } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .tint(AppTheme.recordingRed)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(AppTheme.surface.opacity(0.55)), in: RoundedRectangle(cornerRadius: 14))
                )
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Account")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
        .environmentObject(AuthService.shared)
}
