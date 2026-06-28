import SwiftUI

struct PartControlsView: View {
    @ObservedObject var viewModel: SessionViewModel

    private var totalParts: Int {
        viewModel.selectedSession?.parts.count ?? 0
    }

    private var isFinished: Bool {
        if let partId = viewModel.currentPart?.id {
            return viewModel.sessionState.partStates[partId]?.isFinished ?? false
        }
        return false
    }

    private var hasAudio: Bool {
        if let partId = viewModel.currentPart?.id {
            return !((viewModel.sessionState.partStates[partId]?.audioFileNames.isEmpty) ?? true)
        }
        return false
    }

    var body: some View {
        HStack(spacing: 20) {
            // 左半分: タイマーとステータス
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(viewModel.partElapsedTime))
                    .font(.system(.title, design: .monospaced))
                    .foregroundColor(viewModel.isCurrentPartOvertime ? .orange : .primary)
                statusView
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右半分: アクションボタン
            HStack(spacing: 12) {
                if viewModel.micStatus == .recording {
                    Button(action: { viewModel.pauseRecording() }) {
                        Text("partControls.stop")
                            .frame(minWidth: 80, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("PauseRecordingButton")
                } else {
                    Button(action: { viewModel.startRecording() }) {
                        Text("partControls.start")
                            .frame(minWidth: 80, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFinished || viewModel.micStatus == .starting || viewModel.isFinalizing || viewModel.isGeneratingAIMemo)
                    .accessibilityIdentifier("StartRecordingButton")
                }

                if viewModel.isPlaying {
                    Button(action: { viewModel.stopPlayback() }) {
                        Text("partControls.stopPlayback")
                            .frame(minWidth: 80, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { viewModel.startPlayback() }) {
                        Text("partControls.play")
                            .frame(minWidth: 80, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasAudio || viewModel.micStatus == .recording || viewModel.micStatus == .starting || viewModel.isFinalizing || viewModel.isGeneratingAIMemo)
                }

                Button(action: {
                    Task {
                        await viewModel.finishPart()
                    }
                }) {
                    Text("partControls.finishPart")
                    .frame(minWidth: 80, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isFinished || viewModel.isFinalizing || viewModel.isGeneratingAIMemo)
                .accessibilityIdentifier("FinishPartButton")
            }
        }
        .padding()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    @ViewBuilder
    private var statusView: some View {
        if isFinished {
            Text("partControls.completed")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            switch viewModel.micStatus {
            case .idle:
                Text("partControls.idle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .starting:
                Text("partControls.starting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .recording:
                HStack(spacing: 4) {
                    Text("partControls.recording")
                    AudioWaveformView(amplitude: viewModel.audioAmplitude)
                }
                .font(.caption)
                .foregroundColor(.red)
            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

struct PartControlsView_Previews: PreviewProvider {
    static var previews: some View {
        PartControlsView(
            viewModel: SessionViewModel(micService: MicrophoneService())
        )
    }
}
