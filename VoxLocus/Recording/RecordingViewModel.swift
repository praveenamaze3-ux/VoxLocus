//  Pure MVVM: the View only calls start()/stop()/save() and observes @Published state.

import Foundation
internal import CoreData
import Combine
import FirebaseAuth
internal import _LocationEssentials

@MainActor
final class RecordingViewModel: ObservableObject {

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var liveTranscript = ""
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var lastSavedNote: NoteDTO?
    /// Transcript staged by `stop()`, awaiting a `save()` before it's
    /// actually processed and persisted — lets the user review it first.
    @Published var pendingTranscript: String?

    private let speechService = SpeechRecognitionService()
    private var locationService: LocationGeofenceService
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    /// User-facing status line above the mic — derived from recording state.
    var statusText: String {
        if isRecording {
            return isPaused ? String(localized: "Paused") : String(localized: "Listening…")
        }
        if pendingTranscript != nil {
            return String(localized: "Tap Save to store this note")
        }
        return String(localized: "Tap Start to begin")
    }

    /// True only while actively capturing (not paused) — drives the ambient
    /// glow/blur and the transcript box's recording glow.
    var isActivelyCapturing: Bool { isRecording && !isPaused }

    init(locationService: LocationGeofenceService, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.locationService = locationService
        self.context = context

        speechService.$transcript
            .receive(on: DispatchQueue.main)
            .assign(to: &$liveTranscript)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        speechService.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPaused)
    }

    /// Swaps in the app's shared LocationGeofenceService (injected via
    /// @EnvironmentObject, which isn't available inside View.init()).
    func attach(locationService: LocationGeofenceService) {
        self.locationService = locationService
    }

    /// Requests permissions (if needed) and begins a new recording session.
    func start() {
        pendingTranscript = nil
        lastSavedNote = nil
        lastError = nil
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

    /// Suspends capture without ending the session — the transcript so far
    /// is kept and capture continues from where it left off on `resume()`.
    func pause() {
        speechService.pauseRecording()
    }

    func resume() {
        do {
            try speechService.resumeRecording()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops capture and stages the transcript for review — the note isn't
    /// processed/saved until `save()` is called.
    func stop() {
        let transcript = speechService.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = String(localized: "No speech was captured. Try again and speak clearly into the microphone.")
            return
        }
        pendingTranscript = transcript
    }

    /// Runs the save pipeline on the transcript staged by `stop()`.
    func save() {
        guard let transcript = pendingTranscript else { return }
        pendingTranscript = nil
        Task { await processTranscript(transcript) }
    }

    /// Runs the full background pipeline concurrently where possible.
    private func processTranscript(_ transcript: String) async {
        isProcessing = true
        defer { isProcessing = false }

        // Run NLP extraction and place-name lookup concurrently.
        async let todosTask = NLPTodoExtractor.extractTodos(from: transcript)
        async let placeNameTask = locationService.currentPlaceName()

        let todos = await todosTask
        let placeName = await placeNameTask
        let category = NLPTodoExtractor.suggestCategory(for: transcript)
        let coordinate = locationService.currentLocation?.coordinate

        // Derive a title from the first sentence, same fallback rule as
        // NoteEntity.displayTitle uses for notes that never got a title.
        let now = Date()
        let rawTitle = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = rawTitle.isEmpty
            ? String(localized: "Note \(now.formatted(date: .abbreviated, time: .shortened))")
            : String(rawTitle.prefix(60))

        let noteID = UUID()
        let dto = NoteDTO(
            id: noteID,
            title: title,
            transcript: transcript,
            createdAt: now,
            updatedAt: now,
            category: category.rawValue,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            locationName: placeName,
            todos: todos
        )

        // Push todos to Reminders (non-fatal if it fails — note still saves).
        var finalTodos = todos
        do {
            finalTodos = try await RemindersService.shared.createChecklist(
                for: todos,
                noteTitle: String(transcript.prefix(40))
            )
        } catch {
            lastError = String(localized: "Note saved, but Reminders sync failed: \(error.localizedDescription)")
        }

        var savedDTO = dto
        savedDTO.todos = finalTodos

        do {
            try await saveToCoreData(savedDTO)
            locationService.registerGeofence(for: savedDTO)
            lastSavedNote = savedDTO
            await syncToFirebase(savedDTO)
        } catch {
            lastError = String(localized: "Failed to save note: \(error.localizedDescription)")
        }
    }

    /// Writes on a background context to keep the main actor free.
    private func saveToCoreData(_ dto: NoteDTO) async throws {
        let bgContext = PersistenceController.shared.newBackgroundContext()
        try await bgContext.perform {
            let entity = NoteEntity(context: bgContext)
            entity.id = dto.id
            entity.title = dto.title
            entity.transcript = dto.transcript
            entity.createdAt = dto.createdAt
            entity.updatedAt = dto.updatedAt
            entity.category = dto.category
            entity.latitude = dto.latitude
            entity.longitude = dto.longitude
            entity.locationName = dto.locationName
            entity.todos = dto.todos
            entity.isSyncedToCloud = false
            entity.isSoftDeleted = false
            entity.ownerUID = Auth.auth().currentUser?.uid
            entity.encryptedPayload = try? EncryptionService.encrypt(dto)
            try bgContext.save()
        }
    }

    /// FirebaseSyncService.uploadNote(_:) encrypts and builds the document
    /// internally now, so this just hands off the plain DTO — no separate
    /// encryption step or manual field list here anymore.
    private func syncToFirebase(_ dto: NoteDTO) async {
        if NetworkMonitor.shared.isConnected {
            do {
                try await FirebaseSyncService.shared.uploadNote(dto)
                await markSynced(id: dto.id)
            } catch {
                await SyncRetryQueue.shared.enqueue(dto)
            }
        } else {
            await SyncRetryQueue.shared.enqueue(dto)
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
