import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var viewModel: RecordingViewModel

    init() {
        _viewModel = StateObject(wrappedValue: RecordingViewModel(locationService: LocationGeofenceService()))
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            AmbientRecordingGlow(isActive: viewModel.isActivelyCapturing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // MARK: Mic + status
                MicWaveIndicator(isActive: viewModel.isActivelyCapturing)
                statusText
                transcriptBox
                if !networkMonitor.isConnected {
                    offlineLabel
                }

                Spacer()

                // MARK: Controls
                controlButtons

                // MARK: Result feedback
                if let saved = viewModel.lastSavedNote {
                    savedSummary(saved)
                }
                if let error = viewModel.lastError {
                    errorText(error)
                }

                Spacer()
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.attach(locationService: locationService)
        }
    }

    private var statusText: some View {
        Text(viewModel.statusText)
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 32)
            .padding(.bottom, 10)
            .animation(.easeInOut, value: viewModel.statusText)
    }

    private var offlineLabel: some View {
        Label("Offline — note will sync later", systemImage: "wifi.slash")
            .font(.caption)
            .foregroundStyle(AppTheme.saveAmber)
    }

    /// Start/Stop, Pause/Resume, and (once there's a pending transcript) Save —
    /// grouped so the glass effect blends across whichever buttons are visible.
    private var controlButtons: some View {
        VStack(spacing: 14) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    FullWidthLabelButton(
                        title: viewModel.isRecording ? "Stop" : "Start",
                        systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill",
                        tint: viewModel.isRecording ? AppTheme.recordingRed : AppTheme.accent,
                        disabled: viewModel.isProcessing
                    ) {
                        if viewModel.isRecording { viewModel.stop() } else { viewModel.start() }
                    }

                    FullWidthLabelButton(
                        title: viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill",
                        prominent: false,
                        tint: AppTheme.saveAmber,
                        disabled: !viewModel.isRecording || viewModel.isProcessing
                    ) {
                        if viewModel.isPaused { viewModel.resume() } else { viewModel.pause() }
                    }
                }

                if viewModel.pendingTranscript != nil {
                    FullWidthLabelButton(
                        title: "Save Note",
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.success,
                        disabled: viewModel.isProcessing,
                        action: viewModel.save
                    )
                }
            }

            if viewModel.isProcessing {
                Label("Processing…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 32)
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(AppTheme.recordingRed)
            .padding(.horizontal, 32)
    }

    /// Live transcript, shown below the mic as speech is captured — stays
    /// visible after Stop so the user can review it before tapping Save.
    private var transcriptBox: some View {
        ScrollView {
            Text(viewModel.liveTranscript.isEmpty ? String(localized: "Your speech will appear here…") : viewModel.liveTranscript)
                .font(.body)
                .foregroundStyle(viewModel.liveTranscript.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .animation(.easeInOut, value: viewModel.liveTranscript)
        }
        .frame(maxHeight: 160)
        .themedCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.recordingRed.opacity(viewModel.isActivelyCapturing ? 0.6 : 0), lineWidth: 1.5)
        )
        .shadow(color: AppTheme.recordingRed.opacity(viewModel.isActivelyCapturing ? 0.35 : 0),
                radius: viewModel.isActivelyCapturing ? 16 : 0)
        .animation(.easeInOut(duration: 0.5), value: viewModel.isActivelyCapturing)
        .padding(.horizontal, 32)
        .padding(.top, 34)
    }

    private func savedSummary(_ note: NoteDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Saved as \(NoteCategory.displayName(for: note.category))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
            if !note.todos.isEmpty {
                Text("\(note.todos.count) reminders created:")
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

// MARK: - Ambient Recording Glow

/// A single soft, centered glow that fades in and gently breathes for as
/// long as recording is active — a calmer replacement for the earlier
/// two-blob drifting glow, which read as busy/messy.
private struct AmbientRecordingGlow: View {
    let isActive: Bool
    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(AppTheme.recordingRed.opacity(0.25))
            .frame(width: 320, height: 320)
            .blur(radius: 90)
            .scaleEffect(breathe ? 1.12 : 0.92)
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: isActive)
            .onAppear { startBreathing() }
            .onChange(of: isActive) { _, newValue in if newValue { startBreathing() } }
    }

    private func startBreathing() {
        guard isActive else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            breathe.toggle()
        }
    }
}

// MARK: - Sparkling Ring Indicator

/// A single breathing ring around the mic that continuously sheds small
/// sparkles from its edge, which drift down and fade — like glitter falling
/// off the circle — for as long as recording is active.
struct MicWaveIndicator: View {
    let isActive: Bool

    private let ringRadius: CGFloat = 54

    var body: some View {
        ZStack {
            SparkleFall(ringRadius: ringRadius, isActive: isActive)

            PulsingRing(radius: ringRadius, isActive: isActive)

            Circle()
                .fill(AppTheme.recordingRed.opacity(isActive ? 0.16 : 0.08))
                .frame(width: ringRadius * 1.1, height: ringRadius * 1.1)
                .animation(.easeInOut(duration: 0.3), value: isActive)

            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(isActive ? AppTheme.recordingRed : AppTheme.textSecondary)
                .scaleEffect(isActive ? 1.05 : 1.0)
                .animation(
                    isActive
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.25),
                    value: isActive
                )
        }
        .frame(width: ringRadius * 2.8, height: ringRadius * 2.8)
    }
}

/// The circle around the mic — eases from slightly smaller to slightly
/// larger and back, forever, while recording. Settles to a static, dim ring
/// when not recording.
private struct PulsingRing: View {
    let radius: CGFloat
    let isActive: Bool

    @State private var grow = false

    var body: some View {
        Circle()
            .stroke(AppTheme.recordingRed.opacity(isActive ? 0.6 : 0.2), lineWidth: 2)
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(grow ? 1.08 : 0.96)
            .animation(
                isActive
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.4),
                value: grow
            )
            .onAppear { if isActive { grow = true } }
            .onChange(of: isActive) { _, newValue in grow = newValue }
    }
}

/// A handful of sparkles spawned around the ring's circumference, each one
/// falling and fading independently on its own loop and delay.
private struct SparkleFall: View {
    let ringRadius: CGFloat
    let isActive: Bool

    private let count = 8

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                SparkleParticle(index: i, ringRadius: ringRadius, isActive: isActive)
            }
        }
    }
}

/// One sparkle: it appears on the ring's edge, then drifts down and fades
/// out while shrinking, on a repeating loop with a per-particle delay/speed
/// so the shower reads as scattered rather than synchronized.
private struct SparkleParticle: View {
    let index: Int
    let ringRadius: CGFloat
    let isActive: Bool

    @State private var fallen = false

    private var angle: Double { (Double(index) / 8) * 2 * .pi }
    private var startX: CGFloat { ringRadius * CGFloat(cos(angle)) }
    private var startY: CGFloat { ringRadius * CGFloat(sin(angle)) }
    private var drift: CGFloat { CGFloat((index % 3) - 1) * 6 }
    private var fallDistance: CGFloat { 44 + CGFloat(index % 3) * 10 }
    private var duration: Double { 1.3 + Double(index % 4) * 0.25 }
    private var delay: Double { Double(index) * 0.22 }
    private var symbolSize: CGFloat { index.isMultiple(of: 2) ? 6 : 4 }

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: symbolSize))
            .foregroundStyle(AppTheme.saveAmber)
            .offset(
                x: startX + (fallen ? drift : 0),
                y: fallen ? startY + fallDistance : startY
            )
            .opacity(fallen ? 0 : 0.95)
            .scaleEffect(fallen ? 0.3 : 1.0)
            .animation(
                isActive
                    ? .easeIn(duration: duration).repeatForever(autoreverses: false).delay(delay)
                    : .easeOut(duration: 0.3),
                value: fallen
            )
            .onAppear { if isActive { fallen = true } }
            .onChange(of: isActive) { _, newValue in fallen = newValue }
    }
}

#Preview {
    RecordingView()
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
}
