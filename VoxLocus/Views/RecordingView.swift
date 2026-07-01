//
//  RecordingView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var viewModel: RecordingViewModel

    init() {
        // The real shared LocationGeofenceService is injected later via
        // `attach(locationService:)` in onAppear, since @EnvironmentObject
        // isn't available yet inside View.init().
        _viewModel = StateObject(wrappedValue: RecordingViewModel(locationService: LocationGeofenceService()))
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            recordingIndicator

            Text(viewModel.liveTranscript.isEmpty ? "Listening…" : viewModel.liveTranscript)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .frame(minHeight: 80)
                .animation(.easeInOut, value: viewModel.liveTranscript)

            if !networkMonitor.isConnected {
                Label("Offline — note will sync later", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(action: { viewModel.stopAndProcess() }) {
                Label(viewModel.isProcessing ? "Processing…" : "Stop & Save", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.isProcessing || !viewModel.isRecording)
            .padding(.horizontal, 32)

            if let saved = viewModel.lastSavedNote {
                savedSummary(saved)
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.bottom, 24)
        .onAppear {
            viewModel.attach(locationService: locationService)
            viewModel.startRecordingOnAppear()
        }
    }

    private var recordingIndicator: some View {
        ZStack {
            Circle()
                .fill(.red.opacity(0.15))
                .frame(width: 140, height: 140)
                .scaleEffect(viewModel.isRecording ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isRecording)
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.red)
        }
    }

    private func savedSummary(_ note: NoteDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Saved as \(note.category)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if !note.todos.isEmpty {
                Text("\(note.todos.count) reminder(s) created:")
                    .font(.caption.bold())
                ForEach(note.todos) { todo in
                    Text("• \(todo.text)").font(.caption)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 32)
    }
}

#Preview {
    RecordingView()
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
}
