//
//  RecordingView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
//
//  RecordingView.swift
//  SmartNotes

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var locationService: LocationGeofenceService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var vm = RecordingViewModel(locationService: LocationGeofenceService())

    var body: some View {
        ZStack {
            // Full-screen background
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                waveformOrb
                Spacer()
                transcriptBox
                Spacer()
                controlPanel
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            vm.attach(locationService: locationService)
            vm.start()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("VoxLocus")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [AppTheme.accent, AppTheme.recordingRed],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text(stateLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .animation(.easeInOut, value: vm.recordingState)
        }
        .padding(.top, 16)
    }

    private var stateLabel: String {
        switch vm.recordingState {
        case .idle:       return "TAP START TO RECORD"
        case .recording:  return "● RECORDING"
        case .paused:     return "⏸ PAUSED"
        case .processing: return "⚙ PROCESSING…"
        case .saved:      return "✓ SAVED"
        }
    }

    // MARK: - Waveform orb

    private var waveformOrb: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(orbGlowColor.opacity(0.12))
                .frame(width: 200, height: 200)
                .scaleEffect(vm.recordingState == .recording ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                           value: vm.recordingState)

            // Middle ring
            Circle()
                .fill(orbGlowColor.opacity(0.22))
                .frame(width: 160, height: 160)
                .scaleEffect(vm.recordingState == .recording ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                           value: vm.recordingState)

            // Core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbGlowColor, orbGlowColor.opacity(0.6)],
                        center: .center, startRadius: 10, endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)

            Image(systemName: orbIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: vm.recordingState == .recording)
        }
        .animation(.spring(duration: 0.4), value: vm.recordingState)
    }

    private var orbGlowColor: Color {
        switch vm.recordingState {
        case .recording:  return AppTheme.recordingRed
        case .paused:     return AppTheme.saveAmber
        case .saved:      return AppTheme.success
        case .processing: return AppTheme.accent
        default:          return AppTheme.accent
        }
    }

    private var orbIcon: String {
        switch vm.recordingState {
        case .recording:  return "waveform"
        case .paused:     return "pause.fill"
        case .processing: return "gearshape.fill"
        case .saved:      return "checkmark"
        default:          return "mic.fill"
        }
    }

    // MARK: - Transcript box

    private var transcriptBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.liveTranscript.isEmpty
                 ? (vm.recordingState == .idle ? "Tap Start to begin…" : "Listening…")
                 : vm.liveTranscript)
                .font(.body)
                .foregroundStyle(vm.liveTranscript.isEmpty
                                 ? AppTheme.textSecondary
                                 : AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .animation(.easeInOut, value: vm.liveTranscript)

            if let saved = vm.lastSavedNote {
                Divider().background(AppTheme.border)
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("Saved as \(saved.category)")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.success)
                    Spacer()
                    if !saved.todos.isEmpty {
                        Label("\(saved.todos.count) reminder(s)", systemImage: "checklist")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Label("Open Notes tab to add a location", systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let error = vm.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.recordingRed)
            }

            if !networkMonitor.isConnected {
                Label("Offline — will sync later", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.saveAmber)
            }
        }
        .padding(16)
        .themedCard()
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(spacing: 16) {

            // Primary row: Start / Stop / Resume
            HStack(spacing: 16) {
                switch vm.recordingState {
                case .idle, .saved:
                    // START
                    controlButton(label: "Start", icon: "mic.fill",
                                  color: AppTheme.accent) { vm.start() }

                case .recording:
                    // STOP
                    controlButton(label: "Stop", icon: "stop.fill",
                                  color: AppTheme.recordingRed) { vm.stop() }

                case .paused:
                    // RESUME
                    controlButton(label: "Resume", icon: "mic.fill",
                                  color: AppTheme.accent) { vm.resume() }
                    // DISCARD
                    controlButton(label: "Discard", icon: "trash",
                                  color: AppTheme.textSecondary.opacity(0.6)) { vm.discard() }

                case .processing:
                    ProgressView()
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                }
            }

            // Save button — only when there's content to save
            if (vm.recordingState == .paused || vm.recordingState == .recording),
               !vm.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    vm.save()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save Note")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [AppTheme.saveAmber, AppTheme.saveAmber.opacity(0.8)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(Color(hex: "#0D0F2B"))
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func controlButton(label: String, icon: String, color: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(color.opacity(0.5), lineWidth: 1)
            )
            .foregroundStyle(color)
        }
        .animation(.spring(duration: 0.3), value: vm.recordingState)
    }
}

#Preview {
    RecordingView()
        .environmentObject(LocationGeofenceService())
        .environmentObject(NetworkMonitor.shared)
}
