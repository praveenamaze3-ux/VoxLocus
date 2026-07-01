//
//  AddNoteView.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//
//
//  AddNoteView.swift
//  SmartNotes
//
//  Manual text entry path for creating a note (vs. the voice-recording
//  path in RecordingView). Runs the same NLP extraction -> Reminders ->
//  Core Data save -> encrypt -> Firebase sync pipeline so both paths stay
//  in sync with each other.
//
import SwiftUI
import MapKit
internal import CoreData

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationService: LocationGeofenceService

    @State private var transcript: String = ""
    @State private var selectedCategory: NoteCategory = .other
    @State private var selectedLocation: LocationResult? = nil
    @State private var showLocationSearch = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Note text
                Section("Note") {
                    TextEditor(text: $transcript)
                        .frame(minHeight: 140)
                        .onChange(of: transcript) { _, new in
                            guard !new.isEmpty else { return }
                            selectedCategory = NLPTodoExtractor.suggestCategory(for: new)
                        }
                }

                // MARK: Category
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(NoteCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: Location
                Section {
                    if let loc = selectedLocation {
                        // Show chosen location with a mini map
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.name)
                                        .font(.body.bold())
                                    if !loc.subtitle.isEmpty {
                                        Text(loc.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Button {
                                    selectedLocation = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            // Mini map preview
                            Map(position: .constant(
                                .region(MKCoordinateRegion(
                                    center: loc.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                ))
                            )) {
                                Marker(loc.name, coordinate: loc.coordinate)
                            }
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(true)
                        }
                        .padding(.vertical, 4)

                        Button("Change Location") {
                            showLocationSearch = true
                        }
                        .foregroundStyle(.blue)

                    } else {
                        Button {
                            showLocationSearch = true
                        } label: {
                            Label("Add Location", systemImage: "mappin.and.ellipse")
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Notes with a location will be suggested when you're nearby.")
                        .font(.caption)
                }

                // MARK: Error
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { result in
                    selectedLocation = result
                }
                .environmentObject(locationService)
            }
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        errorMessage = nil
        let text = transcript
        let category = selectedCategory
        let location = selectedLocation

        Task {
            do {
                let todos = await NLPTodoExtractor.extractTodos(from: text)

                var finalTodos = todos
                if !todos.isEmpty {
                    do {
                        finalTodos = try await RemindersService.shared.createChecklist(
                            for: todos, noteTitle: String(text.prefix(40))
                        )
                    } catch {
                        let isXPC = error.localizedDescription.contains("XPC") ||
                                    error.localizedDescription.contains("calaccesssd")
                        if !isXPC { print("Reminders failed: \(error)") }
                    }
                }

                let dto = NoteDTO(
                    id: UUID(),
                    transcript: text,
                    createdAt: Date(),
                    category: category.rawValue,
                    latitude: location?.coordinate.latitude ?? 0,
                    longitude: location?.coordinate.longitude ?? 0,
                    locationName: location?.name,
                    todos: finalTodos
                )

                try await saveToCoreData(dto)

                // Register geofence only if user chose a location
                if location != nil {
                    locationService.registerGeofence(for: dto)
                }

                await syncToFirebase(dto)

                await MainActor.run { isSaving = false; dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveToCoreData(_ dto: NoteDTO) async throws {
        let ctx = PersistenceController.shared.newBackgroundContext()
        try await ctx.performAndSave {
            let entity = NoteEntity(context: ctx)
            entity.id            = dto.id
            entity.transcript    = dto.transcript
            entity.createdAt     = dto.createdAt
            entity.category      = dto.category
            entity.latitude      = dto.latitude
            entity.longitude     = dto.longitude
            entity.locationName  = dto.locationName
            entity.todos         = dto.todos
            entity.isSyncedToCloud   = false
            entity.encryptedPayload  = try? EncryptionService.encrypt(dto)
        }
    }

    private func syncToFirebase(_ dto: NoteDTO) async {
        guard let payload = try? EncryptionService.encrypt(dto) else { return }
        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadEncryptedNote(
                    id: dto.id, encryptedPayload: payload,
                    category: dto.category, createdAt: dto.createdAt
                )
                let ctx = PersistenceController.shared.newBackgroundContext()
                await ctx.perform {
                    let req = NoteEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                    if let e = try? ctx.fetch(req).first {
                        e.isSyncedToCloud = true
                        try? ctx.save()
                    }
                }
            } catch {
                await SyncRetryQueue.shared.enqueue(
                    id: dto.id, payload: payload,
                    category: dto.category, createdAt: dto.createdAt
                )
            }
        } else {
            await SyncRetryQueue.shared.enqueue(
                id: dto.id, payload: payload,
                category: dto.category, createdAt: dto.createdAt
            )
        }
    }
}

#Preview {
    AddNoteView().environmentObject(LocationGeofenceService())
}
