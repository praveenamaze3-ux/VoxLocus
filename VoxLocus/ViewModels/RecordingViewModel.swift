//
//  RecordingViewModel.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

//
//  RecordingViewModel.swift
//  SmartNotes
//
//  Orchestrates: mic recording -> Speech transcription -> NLP todo
//  extraction -> Reminders checklist -> Core Data save -> encrypted
//  Firebase sync -> geofence registration. Pure MVVM: the View only calls
//  start()/stop() and observes @Published state.
//
//
//  RecordingViewModel.swift
//  SmartNotes
//
//  Orchestrates: mic recording -> Speech transcription -> NLP todo
//  extraction -> Reminders checklist -> Core Data save -> encrypted
//  Firebase sync -> geofence registration. Pure MVVM: the View only calls
//  start()/stop() and observes @Published state.
//

import Foundation
internal import CoreData
import Combine

@MainActor
final class RecordingViewModel: ObservableObject {

    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var lastSavedNote: NoteDTO?

    private let speechService = SpeechRecognitionService()
    private var locationService: LocationGeofenceService
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(locationService: LocationGeofenceService, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.locationService = locationService
        self.context = context

        speechService.$transcript
            .receive(on: DispatchQueue.main)
            .assign(to: &$liveTranscript)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        speechService.$authorizationError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.lastError = message
            }
            .store(in: &cancellables)
    }

    /// Swaps in the app's shared LocationGeofenceService (injected via
    /// @EnvironmentObject, which isn't available inside View.init()).
    func attach(locationService: LocationGeofenceService) {
        self.locationService = locationService
    }

    /// Call as soon as the app/recording screen appears.
    func startRecordingOnAppear() {
        Task {
            let granted = await speechService.requestAuthorization()
            guard granted else {
                lastError = speechService.authorizationError
                return
            }
            do {
                try speechService.startRecording()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func stopAndProcess() {
        let transcript = speechService.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            await processTranscript(transcript)
        }
    }

    /// Runs the full background pipeline concurrently where possible.
    private func processTranscript(_ transcript: String) async {
        isProcessing = true
        defer { isProcessing = false }

        let todos    = await NLPTodoExtractor.extractTodos(from: transcript)
        let category = NLPTodoExtractor.suggestCategory(for: transcript)

        let noteID = UUID()
        let dto = NoteDTO(
            id: noteID,
            transcript: transcript,
            createdAt: Date(),
            category: category.rawValue,
            latitude: 0,
            longitude: 0,
            locationName: nil,   // user adds location manually via Notes tab edit
            todos: todos
        )

        // Push todos to Reminders (non-fatal if it fails — note still saves).
        // NOTE: Reminders via EventKit does NOT work in the iOS Simulator
        // (XPC/calaccesssd is unavailable there). This will work on a real device.
        var finalTodos = todos
        if !todos.isEmpty {
            do {
                finalTodos = try await RemindersService.shared.createChecklist(
                    for: todos,
                    noteTitle: String(transcript.prefix(40))
                )
            } catch {
                let isSimulatorXPCError = error.localizedDescription.contains("XPC") ||
                    error.localizedDescription.contains("calaccesssd")
                if !isSimulatorXPCError {
                    lastError = "Note saved, but Reminders sync failed: \(error.localizedDescription)"
                }
                // On simulator: silently continue — note + todos are still
                // saved locally in Core Data and will sync to Reminders on
                // a real device.
            }
        }

        var savedDTO = dto
        savedDTO.todos = finalTodos

        do {
            try await saveToCoreData(savedDTO)
            locationService.registerGeofence(for: savedDTO)
            lastSavedNote = savedDTO
            await syncToFirebase(savedDTO)
        } catch {
            lastError = "Failed to save note: \(error.localizedDescription)"
        }
    }

    /// Writes on a background context to keep the main actor free.
    private func saveToCoreData(_ dto: NoteDTO) async throws {
        let bgContext = PersistenceController.shared.newBackgroundContext()
        try await bgContext.perform {
            let entity = NoteEntity(context: bgContext)
            entity.id = dto.id
            entity.transcript = dto.transcript
            entity.createdAt = dto.createdAt
            entity.category = dto.category
            entity.latitude = dto.latitude
            entity.longitude = dto.longitude
            entity.locationName = dto.locationName
            entity.todos = dto.todos
            entity.isSyncedToCloud = false
            entity.encryptedPayload = try? EncryptionService.encrypt(dto)
            try bgContext.save()
        }
    }

    private func syncToFirebase(_ dto: NoteDTO) async {
        guard let payload = try? EncryptionService.encrypt(dto) else { return }

        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadEncryptedNote(
                    id: dto.id, encryptedPayload: payload, category: dto.category, createdAt: dto.createdAt
                )
                await markSynced(id: dto.id)
            } catch {
                await SyncRetryQueue.shared.enqueue(id: dto.id, payload: payload, category: dto.category, createdAt: dto.createdAt)
            }
        } else {
            await SyncRetryQueue.shared.enqueue(id: dto.id, payload: payload, category: dto.category, createdAt: dto.createdAt)
        }
    }

    private func markSynced(id: UUID) async {
        let bgContext = PersistenceController.shared.newBackgroundContext()
        try? await bgContext.perform {
            let request = NoteEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try bgContext.fetch(request).first {
                entity.isSyncedToCloud = true
                try bgContext.save()
            }
        }
    }
}
