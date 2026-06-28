import SwiftUI

struct SessionToolbarView: View {
    @Binding var selectedSessionId: String
    @ObservedObject var viewModel: SessionViewModel
    let keychainService: KeychainServiceProtocol
    @State private var showingNewSessionSheet = false
    @State private var newSessionName = ""
    @State private var showingRenamePopover = false
    @State private var editedSessionName = ""
    @State private var showingAddPartSheet = false
    @State private var showingSettings = false
    @State private var showImport = false
    @State private var showingSessionDeleteAlert = false
    @State private var showingPartDeleteAlert = false
    @State private var showingPartFullDeleteAlert = false
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
                ForEach(viewModel.sortedSessions) { session in
                    Text(session.name).tag(session.id)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("SessionPicker")
            .frame(maxWidth: 300)

            Button(action: {
                if let session = viewModel.selectedSession {
                    editedSessionName = session.name
                    showingRenamePopover = true
                }
            }) {
                Image(systemName: "pencil")
            }
            .help("セッション名を変更")
            .disabled(viewModel.selectedSession == nil)
            .popover(isPresented: $showingRenamePopover) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("セッション名の変更")
                        .font(.headline)

                    TextField("セッション名", text: $editedSessionName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .onSubmit {
                            saveSessionName()
                        }

                    HStack {
                        Spacer()
                        Button("キャンセル") {
                            showingRenamePopover = false
                        }
                        Button("保存") {
                            saveSessionName()
                        }
                        .disabled(editedSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }

            Button(action: {
                newSessionName = ""
                showingNewSessionSheet = true
            }) {
                Image(systemName: "plus")
            }
            .help("新規セッション追加")
            .sheet(isPresented: $showingNewSessionSheet) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("新しいセッション")
                        .font(.headline)

                    TextField("セッション名", text: $newSessionName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("キャンセル", role: .cancel) {
                            showingNewSessionSheet = false
                        }

                        Button("作成") {
                            viewModel.createEmptySession(name: newSessionName)
                            newSessionName = ""
                            showingNewSessionSheet = false
                        }
                        .disabled(
                            newSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            viewModel.micStatus == .recording ||
                            viewModel.micStatus == .starting
                        )
                    }
                }
                .padding()
                .frame(width: 360)
            }

            Button(action: {
                showingAddPartSheet = true
            }) {
                Label("パート追加", systemImage: "plus.square.fill.on.square.fill")
            }
            .help("パートを追加")
            .disabled(viewModel.micStatus == .recording || viewModel.micStatus == .starting || viewModel.selectedSession == nil)
            .sheet(isPresented: $showingAddPartSheet) {
                PartAddSheet(viewModel: viewModel)
            }

            Menu {
                Button("このセッションを削除", role: .destructive) {
                    showingSessionDeleteAlert = true
                }

                Button("現在のパートを削除", role: .destructive) {
                    showingPartFullDeleteAlert = true
                }
                .disabled(viewModel.currentPart == nil)

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
                .disabled(viewModel.currentPart == nil)
            } label: {
                Image(systemName: "trash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("削除")
            .disabled(
                viewModel.micStatus == .recording ||
                viewModel.micStatus == .starting ||
                viewModel.selectedSession == nil ||
                viewModel.isFinalizing ||
                viewModel.isGeneratingAIMemo
            )
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
            .confirmationDialog("このパートを完全に削除しますか？", isPresented: $showingPartFullDeleteAlert) {
                Button("削除", role: .destructive) {
                    viewModel.deleteCurrentPart()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("音声、文字起こし、AIメモ、分析状態を含むパート情報がすべて削除されます。")
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
                SettingsView(viewModel: viewModel, keychainService: keychainService)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func saveSessionName() {
        let trimmed = editedSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let session = viewModel.selectedSession {
            viewModel.updateSessionName(id: session.id, newName: trimmed)
        }
        showingRenamePopover = false
    }
}
