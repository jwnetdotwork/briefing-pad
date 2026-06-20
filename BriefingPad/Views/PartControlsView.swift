import SwiftUI

struct PartControlsView: View {
    @Binding var currentPartIndex: Int
    let totalParts: Int
    @ObservedObject var micService: MicrophoneService

    private var lastPartIndex: Int {
        max(totalParts - 1, 0)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                Button(action: {
                    if currentPartIndex > 0 {
                        currentPartIndex -= 1
                    }
                }) {
                    Text("[前へ]")
                }
                .disabled(currentPartIndex == 0 || totalParts <= 1)

                VStack {
                    Text("00:02:31") // Dummy timer
                        .font(.system(.title2, design: .monospaced))

                    statusView
                }

                Button(action: {
                    if currentPartIndex < lastPartIndex {
                        currentPartIndex += 1
                    }
                }) {
                    Text("[次へ]")
                }
                .disabled(currentPartIndex >= lastPartIndex || totalParts <= 1)
            }

            HStack(spacing: 60) {
                Button(action: { micService.startRecording() }) {
                    Text("[開始]")
                        .frame(width: 80)
                }
                .disabled(micService.status == .recording)

                Button(action: { micService.stopRecording() }) {
                    Text("[終了]")
                        .frame(width: 80)
                }
                .disabled(micService.status != .recording)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch micService.status {
        case .idle:
            if micService.permissionStatus == .denied {
                Text("マイク許可なし")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("待機中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .recording:
            HStack(spacing: 4) {
                Text("● 録音中")
                Text("/ 音量: \(micService.audioLevel.rawValue)")
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

struct PartControlsView_Previews: PreviewProvider {
    static var previews: some View {
        PartControlsView(
            currentPartIndex: .constant(1),
            totalParts: 5,
            micService: MicrophoneService()
        )
    }
}
