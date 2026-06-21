import SwiftUI

struct SessionToolbarView: View {
    @Binding var selectedSessionId: String
    @ObservedObject var viewModel: SessionViewModel
    let keychainService: KeychainServiceProtocol
    @State private var showingSettings = false

    var body: some View {
        HStack {
            Picker("セッション選択", selection: $selectedSessionId) {
                ForEach(viewModel.sessions) { session in
                    Text(session.name).tag(session.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)

            Button(action: {}) {
                Image(systemName: "plus")
            }
            .help("新規追加")

            Menu {
                Button("このセッションを削除", role: .destructive) {
                    viewModel.deleteCurrentSession()
                }

                Menu("現在のパートのデータを削除") {
                    Button("すべて") {
                        viewModel.deleteCurrentPartData()
                    }
                    Divider()
                    Button("音声のみ") {
                        viewModel.deleteCurrentPartData(onlyAudio: true)
                    }
                    Button("文字起こしのみ") {
                        viewModel.deleteCurrentPartData(onlyTranscript: true)
                    }
                    Button("LLM結果のみ") {
                        viewModel.deleteCurrentPartData(onlyLLM: true)
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("削除")

            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help("設定")
            .sheet(isPresented: $showingSettings) {
                SettingsView(keychainService: keychainService)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

