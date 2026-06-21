import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SessionViewModel
    @StateObject private var micService = MicrophoneService()
    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
        let llmService = OpenAILLMService(keychainService: keychainService)
        let transcriptionService = SpeechTranscriptionService()
        _viewModel = StateObject(wrappedValue: SessionViewModel(
            llmService: llmService,
            transcriptionService: transcriptionService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionToolbarView(
                selectedSessionId: $viewModel.selectedSessionId,
                sessions: viewModel.sessions,
                keychainService: keychainService
            )

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if let session = viewModel.selectedSession {
                        PartListView(
                            parts: session.parts,
                            selectedPartIndex: $viewModel.currentPartIndex
                        )

                        if let part = viewModel.currentPart {
                            PartHeaderView(part: part)

                            Divider()
                                .padding(.horizontal)

                            VStack {
                                PartControlsView(
                                    currentPartIndex: $viewModel.currentPartIndex,
                                    totalParts: session.parts.count,
                                    micService: micService
                                )
                            }
                            .onChange(of: micService.status) {
                                if micService.status == .recording {
                                    viewModel.startTranscription(audioStream: micService.createAudioBufferStream())
                                } else if micService.status == .idle {
                                    viewModel.stopTranscription()
                                }
                            }

                            Divider()
                                .padding(.horizontal)

                            TranscriptView(
                                segments: viewModel.sessionState.partStates[part.id]?.transcript ?? [],
                                errorMessage: viewModel.transcriptionError
                            )

                            LearningPointsView(points: part.learningPoints)

                            ObservationItemsView(
                                items: part.observationItems,
                                state: part.analysisState.observationItemStates
                            )

                            PositiveItemsView(
                                items: part.positiveItems,
                                state: part.analysisState.positiveItemStates
                            )

                            CommentMaterialView(aiMemo: part.aiMemo)
                        } else {
                            Text("現在のパートが見つかりません")
                                .padding()
                        }
                    } else {
                        Text("セッションが見つかりません")
                            .padding()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onChange(of: viewModel.selectedSessionId) {
            viewModel.currentPartIndex = 0
            micService.cancelPendingOperationsAndStop()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
