import SwiftUI

struct PartControlsView: View {
    @Binding var currentPartIndex: Int
    let totalParts: Int
    @Binding var isRecording: Bool

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
                    if isRecording {
                        Text("● 計測中")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("待機中")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                Button(action: { isRecording = true }) {
                    Text("[開始]")
                        .frame(width: 80)
                }
                .disabled(isRecording)

                Button(action: { isRecording = false }) {
                    Text("[終了]")
                        .frame(width: 80)
                }
                .disabled(!isRecording)
            }
        }
        .padding()
    }
}

struct PartControlsView_Previews: PreviewProvider {
    static var previews: some View {
        PartControlsView(
            currentPartIndex: .constant(1),
            totalParts: 5,
            isRecording: .constant(false)
        )
    }
}
