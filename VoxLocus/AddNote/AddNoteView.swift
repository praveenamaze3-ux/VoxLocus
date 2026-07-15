import SwiftUI
import MapKit

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationService: LocationGeofenceService
    @StateObject private var viewModel = AddNoteViewModel()

    @State private var showLocationSearch = false
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Note text
                        ThemedSection(title: "Note", icon: "square.and.pencil") {
                            TextEditor(text: $viewModel.transcript)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(AppTheme.textPrimary)
                                .focused($isNoteFocused)
                        }

                        // MARK: Category
                        ThemedSection(title: "Category", icon: "tag.fill") {
                            CategoryPicker(selection: $viewModel.selectedCategory)
                        }

                        // MARK: Location
                        ThemedSection(title: "Location", icon: "mappin.and.ellipse",
                                      footer: "Notes with a location will be suggested when you're nearby.") {
                            LocationSectionContent(selectedLocation: $viewModel.selectedLocation) {
                                showLocationSearch = true
                            }
                        }

                        // MARK: Error
                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(message: errorMessage)
                        }

                        // MARK: Save button
                        SaveActionButton(
                            idleTitle: "Save Note",
                            systemImage: "square.and.arrow.down.fill",
                            isSaving: viewModel.isSaving,
                            tint: AppTheme.saveAmber,
                            disabled: viewModel.isSaveDisabled,
                            action: { viewModel.save { dismiss() } }
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Note")
            .compactDarkNavBar()
            .toolbar {
                cancelToolbarItem(disabled: viewModel.isSaving) { dismiss() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNoteFocused = false }
                        .foregroundStyle(AppTheme.accent)
                }
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
}
