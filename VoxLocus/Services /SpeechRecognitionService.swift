//
//  SpeechRecognitionService.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//
//  SpeechRecognitionService.swift
//  SmartNotes
//
//  Wraps Speech + AVAudioEngine. Recording starts immediately when requested
//  and streams partial transcripts; stopping finalizes the transcript.
//

import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
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
        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SmartNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }

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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
