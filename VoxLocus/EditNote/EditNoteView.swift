import SwiftUI
import MapKit

struct EditNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationService: LocationGeofenceService
    @StateObject private var viewModel: EditNoteViewModel

    @State private var showLocationSearch = false

    private let note: NoteEntity

    init(note: NoteEntity, viewModel: NotesListViewModel) {
        self.note = note
        _viewModel = StateObject(wrappedValue: EditNoteViewModel(note: note, notesListViewModel: viewModel))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Transcript
                        ThemedSection(title: "Note", icon: "square.and.pencil") {
                            TextEditor(text: $viewModel.transcript)
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        // MARK: Category
                        ThemedSection(title: "Category", icon: "tag.fill") {
                            CategoryPicker(selection: $viewModel.selectedCategory)
                            autoSuggestButton
                        }

                        // MARK: Location
                        ThemedSection(title: "Location", icon: "mappin.and.ellipse",
                                      footer: "Notes with a location will be suggested when you're nearby.") {
                            LocationSectionContent(selectedLocation: $viewModel.selectedLocation) {
                                showLocationSearch = true
                            }
                        }

                        // MARK: To-Dos
                        todosSection

                        // MARK: Error
                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(message: errorMessage)
                        }

                        // MARK: Save button
                        SaveActionButton(
                            idleTitle: "Save Changes",
                            systemImage: "checkmark.circle.fill",
                            isSaving: viewModel.isSaving,
                            tint: AppTheme.accent,
                            disabled: viewModel.isSaveDisabled,
                            action: { viewModel.save { dismiss() } }
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit Note")
            .compactDarkNavBar()
            .dismissWhenDeleted(note)
            .toolbar {
                cancelToolbarItem(disabled: viewModel.isSaving) { dismiss() }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { result in viewModel.selectedLocation = result }
                    .environmentObject(locationService)
            }
            .onAppear {
                viewModel.attach(locationService: locationService)
            }
        }
    }

    // MARK: - Category auto-suggest

    private var autoSuggestButton: some View {
        Button {
            viewModel.applySuggestedCategory()
        } label: {
            Label("Auto-suggest from text", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
        }
        .disabled(viewModel.isAutoSuggestDisabled)
    }

    // MARK: - To-Dos

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            todosHeader
            todosList
            todosFooterActions
        }
        .padding(14)
        .themedCard()
    }

    private var todosHeader: some View {
        HStack {
            Label("TO-DOS", systemImage: "checklist")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            EditButton()
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
    }

    private var todosList: some View {
        ForEach($viewModel.todos) { $todo in
            HStack(spacing: 12) {
                Button { todo.isCompleted.toggle() } label: {
                    Image(systemName: todo.isCompleted
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted
                                         ? AppTheme.success : AppTheme.textSecondary)
                }.buttonStyle(.plain)
                TextField("To-do", text: $todo.text)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.vertical, 4)
            Divider().background(AppTheme.border)
        }
        .onDelete { viewModel.deleteTodos(at: $0) }
        .onMove  { viewModel.moveTodos(from: $0, to: $1) }
    }

    private var todosFooterActions: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.addEmptyTodo()
            } label: {
                Label("Add To-Do", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
            Button {
                viewModel.reExtractTodos()
            } label: {
                Label(viewModel.isExtracting ? "Extracting…" : "Re-extract via NLP",
                      systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
            }
            .disabled(viewModel.isExtracting || viewModel.isAutoSuggestDisabled)
        }
    }
}
