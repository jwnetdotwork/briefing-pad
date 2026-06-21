import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SessionViewModel
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
                viewModel: viewModel,
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
                                PartControlsView(viewModel: viewModel)
                            }

                            Divider()
                                .padding(.horizontal)

                            TranscriptView(
                                segments: viewModel.sessionState.partStates[part.id]?.transcript ?? [],
                                errorMessage: viewModel.transcriptionError
                            )

                            // LearningPointsView is hidden in Phase 5 Dashboard

                            ObservationItemsView(
                                items: part.observationItems,
                                state: part.analysisState.observationItemStates
                            )

                            PositiveItemsView(
                                items: part.positiveItems,
                                state: part.analysisState.positiveItemStates
                            )

                            CommentMaterialView(
                                aiMemo: part.aiMemo,
                                isFinalizing: viewModel.isFinalizing
                            )
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
