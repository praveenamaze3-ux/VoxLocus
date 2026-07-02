//
//  NoteListView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//  NotesListView.swift
//  SmartNotes

import SwiftUI
internal import CoreData

struct NotesListView: View {
    @StateObject var viewModel: NotesListViewModel
    @EnvironmentObject var locationService: LocationGeofenceService
    @State private var showingAddNote = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Multi-layer gradient background — gives depth to the dark theme
                LinearGradient(
                    colors: [
                        Color(hex: "#0A0C24"),
                        Color(hex: "#0D0F2B"),
                        Color(hex: "#111435")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Subtle radial glow in top-left for visual interest
                RadialGradient(
                    colors: [AppTheme.accent.opacity(0.15), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 340
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !viewModel.nearbySuggestions.isEmpty {
                        nearbyBanner
                    }

                    FilterBarView(
                        selectedCategory: $viewModel.selectedCategory,
                        showOnlyWithTodos: $viewModel.showOnlyWithTodos,
                        showOnlyNearby: $viewModel.showOnlyNearby
                    )

                    if viewModel.filteredNotes.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.filteredNotes) { note in
                                    NavigationLink {
                                        NoteDetailView(note: note, viewModel: viewModel)
                                    } label: {
                                        NoteRow(note: note)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            viewModel.delete(note)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("My Notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(hex: "#0A0C24"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddNote = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search notes…")
            .sheet(isPresented: $showingAddNote) {
                AddNoteView().environmentObject(locationService)
            }
        }
        // Force dark mode so system components (search bar, nav title,
        // alerts) all adopt the dark palette instead of overriding to white.
        .preferredColorScheme(.dark)
    }

    // MARK: - Nearby banner

    private var nearbyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .foregroundStyle(AppTheme.saveAmber)
            Text("You're near \(viewModel.nearbySuggestions.count) saved note(s)")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.saveAmber)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.saveAmber.opacity(0.12))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent.opacity(0.5))
            Text("No Notes Yet")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Tap + to add a note, or record one from the Record tab.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - NoteRow with blur glass card

private struct NoteRow: View {
    @ObservedObject var note: NoteEntity

    var body: some View {
        guard note.isAccessible else { return AnyView(EmptyView()) }
        return AnyView(glassCard)
    }

    private var categoryColor: Color {
        AppTheme.categoryColor(for: note.safeCategory)
    }

    private var glassCard: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Category pill + date
            HStack {
                let cat = note.safeCategory
                if !cat.isEmpty {
                    Label(cat, systemImage: NoteCategory(rawValue: cat)?.systemImage ?? "tag")
                        .font(.caption.bold())
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(categoryColor.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(categoryColor.opacity(0.35), lineWidth: 0.8))
                }
                Spacer()
                Text(note.safeCreatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Transcript preview
            Text(note.safeTranscript)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Footer chips
            HStack(spacing: 10) {
                if let loc = note.safeLocationName, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.fill")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if !note.safeTodos.isEmpty {
                    Label("\(note.safeTodos.count)", systemImage: "checklist")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.success.opacity(0.12), in: Capsule())
                }
                Image(systemName: note.safeIsSynced ? "lock.icloud.fill" : "icloud.and.arrow.up")
                    .font(.caption2)
                    .foregroundStyle(note.safeIsSynced ? AppTheme.success : AppTheme.saveAmber)
            }
        }
        .padding(16)
        // Frosted glass effect: blur material + dark tint overlay + border
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "#1A1D4E").opacity(0.55))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppTheme.accent.opacity(0.35),
                            AppTheme.border.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.accent.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NotesListView(viewModel: NotesListViewModel(
        context: PersistenceController.preview.container.viewContext,
        locationService: LocationGeofenceService()
    ))
    .environmentObject(LocationGeofenceService())
}
