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

enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing
    case saved
}

@MainActor
final class RecordingViewModel: ObservableObject {

    @Published var recordingState: RecordingState = .idle
    @Published var liveTranscript = ""
    @Published var lastError: String?
    @Published var lastSavedNote: NoteDTO?

    var locationService: LocationGeofenceService
    private let speechService  = SpeechRecognitionService()
    private let context: NSManagedObjectContext
    private var cancellables   = Set<AnyCancellable>()

    init(locationService: LocationGeofenceService,
         context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.locationService = locationService
        self.context         = context

        speechService.$transcript
            .receive(on: DispatchQueue.main)
            .assign(to: &$liveTranscript)

        speechService.$authorizationError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.lastError = msg }
            .store(in: &cancellables)
    }

    func attach(locationService: LocationGeofenceService) {
        self.locationService = locationService
    }

    // MARK: - Controls

    /// Requests permissions and starts capturing.
    func start() {
        lastError = nil
        lastSavedNote = nil
        Task {
            let granted = await speechService.requestAuthorization()
            guard granted else { lastError = speechService.authorizationError; return }
            do {
                try speechService.startRecording()
                recordingState = .recording
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Pauses capture — transcript is preserved.
    func stop() {
        speechService.stopRecording()
        recordingState = .paused
    }

    /// Resumes capture, appending to the existing transcript.
    func resume() {
        lastError = nil
        Task {
            do {
                // Keep previous transcript; new audio appends via the recogniser.
                try speechService.startRecording()
                recordingState = .recording
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Runs the NLP → Reminders → CoreData → Firebase pipeline.
    func save() {
        let transcript = liveTranscript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        speechService.stopRecording()
        recordingState = .processing

        Task {
            await processTranscript(transcript)
        }
    }

    /// Discards the current session and resets to idle.
    func discard() {
        speechService.stopRecording()
        liveTranscript = ""
        lastSavedNote  = nil
        lastError      = nil
        recordingState = .idle
    }

    // MARK: - Pipeline

    private func processTranscript(_ transcript: String) async {
        let todos    = await NLPTodoExtractor.extractTodos(from: transcript)
        let category = NLPTodoExtractor.suggestCategory(for: transcript)

        var finalTodos = todos
        if !todos.isEmpty {
            do {
                finalTodos = try await RemindersService.shared.createChecklist(
                    for: todos, noteTitle: String(transcript.prefix(40))
                )
            } catch {
                let isXPC = error.localizedDescription.contains("XPC") ||
                            error.localizedDescription.contains("calaccesssd")
                if !isXPC { lastError = "Reminders sync failed: \(error.localizedDescription)" }
            }
        }

        let dto = NoteDTO(
            id: UUID(),
            transcript: transcript,
            createdAt: Date(),
            category: category.rawValue,
            latitude: 0,
            longitude: 0,
            locationName: nil,
            todos: finalTodos
        )

        do {
            try await saveToCoreData(dto)
            lastSavedNote  = dto
            recordingState = .saved
            liveTranscript = ""
            await syncToFirebase(dto)
        } catch {
            lastError      = "Failed to save: \(error.localizedDescription)"
            recordingState = .paused
        }
    }

    private func saveToCoreData(_ dto: NoteDTO) async throws {
        let bgCtx = PersistenceController.shared.newBackgroundContext()
        try await bgCtx.performAndSave {
            let entity = NoteEntity(context: bgCtx)
            entity.id               = dto.id
            entity.transcript       = dto.transcript
            entity.createdAt        = dto.createdAt
            entity.category         = dto.category
            entity.latitude         = dto.latitude
            entity.longitude        = dto.longitude
            entity.locationName     = dto.locationName
            entity.todos            = dto.todos
            entity.isSyncedToCloud  = false
            entity.encryptedPayload = try? EncryptionService.encrypt(dto)
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
                let bgCtx = PersistenceController.shared.newBackgroundContext()
                await bgCtx.perform {
                    let req = NoteEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
                    if let e = try? bgCtx.fetch(req).first {
                        e.isSyncedToCloud = true; try? bgCtx.save()
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
