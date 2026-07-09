
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    /// True when a session is active but capture is temporarily suspended.
    @Published var isPaused: Bool = false
    @Published var authorizationError: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Requests mic + speech permissions. Call before `startRecording()`.
    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard speechStatus == .authorized, micGranted else {
            authorizationError = "Microphone or Speech Recognition permission was denied. Enable it in Settings."
            return false
        }
        return true
    }

    func startRecording() throws {
        // Cancel any ongoing task.
        task?.cancel()
        task = nil

        // Check availability before touching the audio session/engine, so a
        // failure here doesn't leave the engine started with no task
        // consuming its buffers (which broke the next recording attempt too).
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SmartNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // NOTE: on-device recognition is more private but is unreliable on
        // simulators and some devices/locales — only opt in if you've
        // verified it works on your test hardware. Server-based (default)
        // is far more reliable for development.
        // if recognizer?.supportsOnDeviceRecognition == true {
        //     req.requiresOnDeviceRecognition = true
        // }
        self.request = req

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        isPaused = false
        transcript = ""

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self.authorizationError = "Recognition error: \(error.localizedDescription)"
                    self.stopAudioEngine()
                } else if result?.isFinal ?? false {
                    self.stopAudioEngine()
                }
            }
        }
    }

    /// Suspends audio capture without ending the recognition session, so
    /// `transcript` keeps accumulating across a later `resumeRecording()`
    /// instead of being reset like a full `stopRecording()` would do.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioEngine.pause()
        isPaused = true
    }

    /// Resumes capture on the same recognition session that was suspended
    /// by `pauseRecording()`.
    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        try audioEngine.start()
        isPaused = false
    }

    /// Stops capture and returns the final transcript string.
    @discardableResult
    func stopRecording() -> String {
        stopAudioEngine()
        task?.finish()
        let final = transcript
        return final
    }

    private func stopAudioEngine() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
