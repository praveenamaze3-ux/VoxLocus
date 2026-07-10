import SwiftUI
internal import CoreData

struct NotesListView: View {
    @StateObject var viewModel: NotesListViewModel
    @State private var showingAddNote = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.background, AppTheme.surfaceRaised],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                NotesAmbientBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !viewModel.nearbySuggestions.isEmpty {
                        nearbyBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    FilterBarView(
                        selectedCategory: $viewModel.selectedCategory,
                        showOnlyWithTodos: $viewModel.showOnlyWithTodos,
                        showOnlyNearby: $viewModel.showOnlyNearby
                    )

                    List {
                        ForEach(viewModel.filteredNotes) { note in
                            NavigationLink {
                                NoteDetailView(note: note, viewModel: viewModel)
                            } label: {
                                NoteRow(note: note)
                                    .padding(12)
                                    .themedCard()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        .onDelete { indices in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                for index in indices {
                                    viewModel.delete(viewModel.filteredNotes[index])
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.surface.opacity(0.45).ignoresSafeArea())
                    .searchable(text: $viewModel.searchText, prompt: "Search notes")
                    .overlay {
                        if viewModel.filteredNotes.isEmpty {
                            ContentUnavailableView(
                                "No Notes Yet",
                                systemImage: "note.text",
                                description: Text("Record your first thought from the Record tab.")
                            )
                            .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.nearbySuggestions.isEmpty)
                .animation(.easeInOut(duration: 0.25), value: viewModel.filteredNotes.isEmpty)
            }
            .navigationTitle("Smart Notes")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(AppTheme.accent)
                }
            }
            .sheet(isPresented: $showingAddNote) {
                AddNoteView()
            }
        }
    }

    private var nearbyBanner: some View {
        HStack {
            Image(systemName: "location.fill")
            Text("You're near a place with \(viewModel.nearbySuggestions.count) saved note(s).")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(10)
        .background(AppTheme.saveAmber.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.saveAmber.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// Slow-drifting, heavily-blurred color blobs in theme colors — gives the
/// otherwise flat background some depth without competing with the frosted
/// filter bar / list panels drawn on top of it.
private struct NotesAmbientBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            blob(color: AppTheme.accent,    size: 240, x: drift ? -90 : -130, y: drift ? -260 : -220)
            blob(color: AppTheme.saveAmber, size: 200, x: drift ?  120 :  150, y: drift ?   80 :   40)
            blob(color: AppTheme.success,   size: 220, x: drift ?  -60 :  -20, y: drift ?  430 :  470)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.16))
            .frame(width: size, height: size)
            .blur(radius: 80)
            .offset(x: x, y: y)
    }
}

private struct NoteRow: View {
    @ObservedObject var note: NoteEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let category = note.category {
                    Label(category, systemImage: NoteCategory(rawValue: category)?.systemImage ?? "tag")
                        .font(.caption)
                        .foregroundStyle(AppTheme.categoryColor(for: category))
                }
                Spacer()
                Text(note.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            // Show explicit title or first sentence.
            Text(note.displayTitle)
                .font(.body.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
            Text(note.transcript ?? "")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                if let loc = note.locationName, !loc.isEmpty {
                    Label(loc, systemImage: "mappin")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if !note.todos.isEmpty {
                    Label("\(note.todos.count) to-do(s)", systemImage: "checklist")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.success)
                }
                if !note.isSyncedToCloud {
                    Label("Pending sync", systemImage: "icloud.and.arrow.up")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.saveAmber)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NotesListView(viewModel: NotesListViewModel(
        context: PersistenceController.preview.container.viewContext,
        locationService: LocationGeofenceService()
    ))
}
