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
            Picker("sessionToolbar.sessionPicker", selection: sessionBinding) {
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
            .help("sessionToolbar.help.renameSession")
            .disabled(viewModel.selectedSession == nil)
            .popover(isPresented: $showingRenamePopover) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("sessionToolbar.renameSessionTitle")
                        .font(.headline)

                    TextField("sessionToolbar.sessionName", text: $editedSessionName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .onSubmit {
                            saveSessionName()
                        }

                    HStack {
                        Spacer()
                        Button("common.cancel") {
                            showingRenamePopover = false
                        }
                        Button("common.save") {
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
            .help("sessionToolbar.help.newSession")
            .sheet(isPresented: $showingNewSessionSheet) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("sessionToolbar.newSessionTitle")
                        .font(.headline)

                    TextField("sessionToolbar.sessionName", text: $newSessionName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("common.cancel", role: .cancel) {
                            showingNewSessionSheet = false
                        }

                        Button("common.create") {
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
                Label("sessionToolbar.addPart", systemImage: "plus.square.fill.on.square.fill")
            }
            .help("sessionToolbar.help.addPart")
            .disabled(viewModel.micStatus == .recording || viewModel.micStatus == .starting || viewModel.selectedSession == nil)
            .sheet(isPresented: $showingAddPartSheet) {
                PartAddSheet(viewModel: viewModel)
            }

            Menu {
                Button("sessionToolbar.deleteCurrentSession", role: .destructive) {
                    showingSessionDeleteAlert = true
                }

                Button("sessionToolbar.deleteCurrentPart", role: .destructive) {
                    showingPartFullDeleteAlert = true
                }
                .disabled(viewModel.currentPart == nil)

                Menu("sessionToolbar.deleteCurrentPartData") {
                    Button("common.all") {
                        partDeleteMode = .all
                        showingPartDeleteAlert = true
                    }
                    Divider()
                    Button("common.audioOnly") {
                        partDeleteMode = .audio
                        showingPartDeleteAlert = true
                    }
                    Button("common.transcriptOnly") {
                        partDeleteMode = .transcript
                        showingPartDeleteAlert = true
                    }
                    Button("common.llmOnly") {
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
            .help("common.delete")
            .disabled(
                viewModel.micStatus == .recording ||
                viewModel.micStatus == .starting ||
                viewModel.selectedSession == nil ||
                viewModel.isFinalizing ||
                viewModel.isGeneratingAIMemo
            )
            .confirmationDialog("sessionToolbar.confirmDeleteSessionTitle", isPresented: $showingSessionDeleteAlert) {
                Button("common.delete", role: .destructive) {
                    viewModel.deleteCurrentSession()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("sessionToolbar.confirmDeleteSessionMessage")
            }
            .confirmationDialog("sessionToolbar.confirmDeletePartDataTitle", isPresented: $showingPartDeleteAlert) {
                Button("common.delete", role: .destructive) {
                    switch partDeleteMode {
                    case .all: viewModel.deleteCurrentPartData()
                    case .audio: viewModel.deleteCurrentPartData(onlyAudio: true)
                    case .transcript: viewModel.deleteCurrentPartData(onlyTranscript: true)
                    case .llm: viewModel.deleteCurrentPartData(onlyLLM: true)
                    }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("sessionToolbar.confirmDeletePartDataMessage")
            }
            .confirmationDialog("sessionToolbar.confirmDeletePartTitle", isPresented: $showingPartFullDeleteAlert) {
                Button("common.delete", role: .destructive) {
                    viewModel.deleteCurrentPart()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("sessionToolbar.confirmDeletePartMessage")
            }

            Spacer()

            Button(action: { showImport = true }) {
                Label("sessionToolbar.importNotion", systemImage: "square.and.arrow.down")
            }
            .help("sessionToolbar.help.importNotion")
            .sheet(isPresented: $showImport) {
                NotionImportSheet(viewModel: viewModel, keychainService: keychainService)
            }

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help("sessionToolbar.help.settings")
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
