import SwiftUI

struct SessionToolbarView: View {
    @Binding var selectedSessionId: String
    @ObservedObject var viewModel: SessionViewModel
    let keychainService: KeychainServiceProtocol
    @State private var showingSettings = false
    @State private var showImport = false
    @State private var showingSessionDeleteAlert = false
    @State private var showingPartDeleteAlert = false
    @State private var partDeleteMode: PartDeleteMode = .all

    enum PartDeleteMode {
        case all, audio, transcript, llm
    }

    var body: some View {
        let sessionBinding = Binding<String>(
            get: { selectedSessionId },
            set: { viewModel.selectSession(id: $0) }
        )

        HStack {
            Picker("セッション選択", selection: sessionBinding) {
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
                    showingSessionDeleteAlert = true
                }

                Menu("現在のパートのデータを削除") {
                    Button("すべて") {
                        partDeleteMode = .all
                        showingPartDeleteAlert = true
                    }
                    Divider()
                    Button("音声のみ") {
                        partDeleteMode = .audio
                        showingPartDeleteAlert = true
                    }
                    Button("文字起こしのみ") {
                        partDeleteMode = .transcript
                        showingPartDeleteAlert = true
                    }
                    Button("LLM結果のみ") {
                        partDeleteMode = .llm
                        showingPartDeleteAlert = true
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("削除")
            .disabled(viewModel.micStatus == .recording || viewModel.micStatus == .starting || viewModel.selectedSession == nil)
            .confirmationDialog("セッションを完全に削除しますか？", isPresented: $showingSessionDeleteAlert) {
                Button("削除", role: .destructive) {
                    viewModel.deleteCurrentSession()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("このセッションは一覧からも消え、保存済みデータも削除されます。")
            }
            .confirmationDialog("パートのデータを削除しますか？", isPresented: $showingPartDeleteAlert) {
                Button("削除", role: .destructive) {
                    switch partDeleteMode {
                    case .all: viewModel.deleteCurrentPartData()
                    case .audio: viewModel.deleteCurrentPartData(onlyAudio: true)
                    case .transcript: viewModel.deleteCurrentPartData(onlyTranscript: true)
                    case .llm: viewModel.deleteCurrentPartData(onlyLLM: true)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("選択したパートのデータが削除されます。")
            }

            Spacer()

            Button(action: { showImport = true }) {
                Label("Notionインポート", systemImage: "square.and.arrow.down")
            }
            .help("Notion からインポート")
            .sheet(isPresented: $showImport) {
                NotionImportSheet(viewModel: viewModel, keychainService: keychainService)
            }

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
