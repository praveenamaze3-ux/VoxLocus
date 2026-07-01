//
//  ContentView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import SwiftUI
internal import CoreData

struct ContentView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        TabView {
            RecordingView()
                .tabItem { Label("Record", systemImage: "mic.fill") }

            NotesListView(viewModel: NotesListViewModel(context: context, locationService: locationService))
                .tabItem { Label("Notes", systemImage: "note.text") }
        }
        .onAppear {
            locationService.requestPermission()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
}
