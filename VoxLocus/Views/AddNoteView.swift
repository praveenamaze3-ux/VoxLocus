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
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Note text
                        themedSection(title: "Note", icon: "square.and.pencil") {
                            TextEditor(text: $transcript)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(AppTheme.textPrimary)
                                .onChange(of: transcript) { _, new in
                                    guard !new.isEmpty else { return }
                                    selectedCategory = NLPTodoExtractor.suggestCategory(for: new)
                                }
                        }

                        // MARK: Category
                        themedSection(title: "Category", icon: "tag.fill") {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(NoteCategory.allCases) { cat in
                                    Label(cat.rawValue, systemImage: cat.systemImage)
                                        .tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppTheme.accent)
                            .foregroundStyle(AppTheme.textPrimary)
                        }

                        // MARK: Location
                        themedSection(title: "Location", icon: "mappin.and.ellipse",
                                      footer: "Notes with a location will be suggested when you're nearby.") {
                            if let loc = selectedLocation {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundStyle(AppTheme.recordingRed)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(loc.name)
                                                .font(.body.bold())
                                                .foregroundStyle(AppTheme.textPrimary)
                                            if !loc.subtitle.isEmpty {
                                                Text(loc.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            selectedLocation = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Map(position: .constant(.region(MKCoordinateRegion(
                                        center: loc.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )))) {
                                        Marker(loc.name, coordinate: loc.coordinate)
                                            .tint(AppTheme.recordingRed)
                                    }
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .disabled(true)

                                    Button("Change Location") { showLocationSearch = true }
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.accent)
                                }
                            } else {
                                Button {
                                    showLocationSearch = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                        Text("Add Location")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.accent.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // MARK: Error
                        if let errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(errorMessage).font(.caption)
                            }
                            .foregroundStyle(AppTheme.recordingRed)
                            .padding(12)
                            .background(AppTheme.recordingRed.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }

                        // MARK: Save button
                        Button {
                            save()
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(AppTheme.background)
                                } else {
                                    Image(systemName: "square.and.arrow.down.fill")
                                }
                                Text(isSaving ? "Saving…" : "Save Note")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
                                    ? AppTheme.saveAmber.opacity(0.3)
                                    : AppTheme.saveAmber,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(AppTheme.background)
                        }
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                        .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { result in selectedLocation = result }
                    .environmentObject(locationService)
            }
        }
    }

    // MARK: - Themed section builder

    @ViewBuilder
    private func themedSection<Content: View>(
        title: String,
        icon: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            content()
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .themedCard()
    }

    // MARK: - Save

    private func save() {
        isSaving = true; errorMessage = nil
        let text = transcript; let category = selectedCategory; let location = selectedLocation
        Task {
            do {
                let todos = await NLPTodoExtractor.extractTodos(from: text)
                var finalTodos = todos
                if !todos.isEmpty {
                    do {
                        finalTodos = try await RemindersService.shared.createChecklist(
                            for: todos, noteTitle: String(text.prefix(40)))
                    } catch {
                        let isXPC = error.localizedDescription.contains("XPC") ||
                                    error.localizedDescription.contains("calaccesssd")
                        if !isXPC { print("Reminders: \(error)") }
                    }
                }
                let dto = NoteDTO(id: UUID(), transcript: text, createdAt: Date(),
                                  category: category.rawValue,
                                  latitude: location?.coordinate.latitude ?? 0,
                                  longitude: location?.coordinate.longitude ?? 0,
                                  locationName: location?.name, todos: finalTodos)
                try await saveToCoreData(dto)
                if location != nil { locationService.registerGeofence(for: dto) }
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
            let e = NoteEntity(context: ctx)
            e.id = dto.id; e.transcript = dto.transcript; e.createdAt = dto.createdAt
            e.category = dto.category; e.latitude = dto.latitude; e.longitude = dto.longitude
            e.locationName = dto.locationName; e.todos = dto.todos
            e.isSyncedToCloud = false; e.encryptedPayload = try? EncryptionService.encrypt(dto)
        }
    }

    private func syncToFirebase(_ dto: NoteDTO) async {
        guard let payload = try? EncryptionService.encrypt(dto) else { return }
        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadEncryptedNote(
                    id: dto.id, encryptedPayload: payload, category: dto.category, createdAt: dto.createdAt)
                let ctx = PersistenceController.shared.newBackgroundContext()
                await ctx.perform {
                    let req = NoteEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                    if let e = try? ctx.fetch(req).first { e.isSyncedToCloud = true; try? ctx.save() }
                }
            } catch {
                await SyncRetryQueue.shared.enqueue(id: dto.id, payload: payload, category: dto.category, createdAt: dto.createdAt)
            }
        } else {
            await SyncRetryQueue.shared.enqueue(id: dto.id, payload: payload, category: dto.category, createdAt: dto.createdAt)
        }
    }
}
