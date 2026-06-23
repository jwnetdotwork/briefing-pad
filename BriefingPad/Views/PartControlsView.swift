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
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                Button(action: { viewModel.moveToPreviousPart() }) {
                    Text("前へ")
                }
                .disabled(viewModel.currentPartIndex == 0 || totalParts <= 1 || viewModel.isFinalizing)

                VStack {
                    Text(formatTime(viewModel.partElapsedTime))
                        .font(.system(.title2, design: .monospaced))

                    statusView
                }
                .frame(minWidth: 200)

                Button(action: { viewModel.moveToNextPart() }) {
                    Text("次へ")
                }
                .disabled(viewModel.currentPartIndex >= (totalParts - 1) || totalParts <= 1 || viewModel.isFinalizing)
            }

            HStack(spacing: 40) {
                if viewModel.micStatus == .recording {
                    Button(action: { viewModel.pauseRecording() }) {
                        Text("停止")
                            .frame(width: 80)
                    }
                } else {
                    Button(action: { viewModel.startRecording() }) {
                        Text("開始")
                            .frame(width: 80)
                    }
                    .disabled(isFinished || viewModel.micStatus == .starting || viewModel.isFinalizing)
                }

                if viewModel.isPlaying {
                    Button(action: { viewModel.stopPlayback() }) {
                        Text("再生停止")
                            .frame(width: 80)
                    }
                } else {
                    Button(action: { viewModel.startPlayback() }) {
                        Text("再生")
                            .frame(width: 80)
                    }
                    .disabled(!hasAudio || viewModel.micStatus == .recording || viewModel.micStatus == .starting || viewModel.isFinalizing)
                }

                Button(action: {
                    Task {
                        await viewModel.finishPart()
                    }
                }) {
                    Text("パート終了")
                        .frame(width: 80)
                }
                .disabled(isFinished || viewModel.isFinalizing)
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
            Text("完了済み")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            switch viewModel.micStatus {
            case .idle:
                Text("待機中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .starting:
                Text("準備中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .recording:
                HStack(spacing: 4) {
                    Text("● 録音中")
                    Text("/ 音量: \(viewModel.audioLevel.rawValue)")
                        .frame(width: 80, alignment: .leading)
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
            viewModel: SessionViewModel()
        )
    }
}
