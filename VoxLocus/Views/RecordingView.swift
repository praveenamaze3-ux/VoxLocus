import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var viewModel: RecordingViewModel

    init() {
        _viewModel = StateObject(wrappedValue: RecordingViewModel(locationService: LocationGeofenceService()))
    }

    private var statusText: String {
        if viewModel.isRecording {
            return viewModel.isPaused ? "Paused" : "Listening…"
        }
        if viewModel.pendingTranscript != nil {
            return "Tap Save to store this note"
        }
        return "Tap Start to begin"
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                MicWaveIndicator(isActive: viewModel.isRecording && !viewModel.isPaused)

                Text(statusText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut, value: statusText)

                transcriptBox

                if !networkMonitor.isConnected {
                    Label("Offline — note will sync later", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(AppTheme.saveAmber)
                }

                Spacer()

                VStack(spacing: 14) {
                    GlassEffectContainer(spacing: 14) {
                        HStack(spacing: 14) {
                            Button {
                                if viewModel.isRecording {
                                    viewModel.stop()
                                } else {
                                    viewModel.start()
                                }
                            } label: {
                                Label(viewModel.isRecording ? "Stop" : "Start",
                                      systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.glassProminent)
                            .tint(viewModel.isRecording ? AppTheme.recordingRed : AppTheme.accent)
                            .disabled(viewModel.isProcessing)

                            Button {
                                if viewModel.isPaused {
                                    viewModel.resume()
                                } else {
                                    viewModel.pause()
                                }
                            } label: {
                                Label(viewModel.isPaused ? "Resume" : "Pause",
                                      systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.glass)
                            .tint(AppTheme.saveAmber)
                            .disabled(!viewModel.isRecording || viewModel.isProcessing)
                        }

                        if viewModel.pendingTranscript != nil {
                            Button {
                                viewModel.save()
                            } label: {
                                Label("Save Note", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.glassProminent)
                            .tint(AppTheme.success)
                            .disabled(viewModel.isProcessing)
                        }
                    }

                    if viewModel.isProcessing {
                        Label("Processing…", systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 32)

                if let saved = viewModel.lastSavedNote {
                    savedSummary(saved)
                }

                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppTheme.recordingRed)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.attach(locationService: locationService)
        }
    }

    /// Live transcript, shown below the mic as speech is captured — stays
    /// visible after Stop so the user can review it before tapping Save.
    private var transcriptBox: some View {
        ScrollView {
            Text(viewModel.liveTranscript.isEmpty ? "Your speech will appear here…" : viewModel.liveTranscript)
                .font(.body)
                .foregroundStyle(viewModel.liveTranscript.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .animation(.easeInOut, value: viewModel.liveTranscript)
        }
        .frame(maxHeight: 160)
        .themedCard()
        .padding(.horizontal, 32)
    }

    private func savedSummary(_ note: NoteDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Saved as \(note.category)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
            if !note.todos.isEmpty {
                Text("\(note.todos.count) reminder(s) created:")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                ForEach(note.todos) { todo in
                    Text("• \(todo.text)").font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding()
        .themedCard()
        .padding(.horizontal, 32)
    }
}

// MARK: - Dotted Wave Ring (replaces three-circle overlay)

/// 16 dots arranged in a ring. While actively capturing, each dot pulses
/// easeInOut with a per-dot stagger, giving a travelling-wave appearance.
/// Paused sessions freeze the animation to visually distinguish from Stopped.
struct MicWaveIndicator: View {
    let isActive: Bool
    @State private var animating = false

    private let dotCount     = 16
    private let ringRadius: CGFloat = 68
    private let dotSize:    CGFloat = 7

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let angle  = Angle(degrees: Double(i) / Double(dotCount) * 360)
                let delay  = Double(i) / Double(dotCount) * 0.7

                Circle()
                    .fill(AppTheme.recordingRed.opacity(isActive ? 0.85 : 0.20))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1.6 : 0.7)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.7)
                                .repeatForever(autoreverses: true)
                                .delay(delay)
                            : .easeInOut(duration: 0.25),
                        value: animating
                    )
                    .offset(
                        x: ringRadius * CGFloat(cos(angle.radians)),
                        y: ringRadius * CGFloat(sin(angle.radians))
                    )
            }

            // Mic icon at centre
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundStyle(isActive ? AppTheme.recordingRed : AppTheme.textSecondary)
                .scaleEffect(isActive ? 1.06 : 1.0)
                .animation(
                    isActive
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.25),
                    value: isActive
                )
        }
        .frame(
            width:  (ringRadius + dotSize) * 2 + 10,
            height: (ringRadius + dotSize) * 2 + 10
        )
        .onAppear { if isActive { animating = true } }
        .onChange(of: isActive) { _, newValue in animating = newValue }
    }
}

#Preview {
    RecordingView()
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
}
