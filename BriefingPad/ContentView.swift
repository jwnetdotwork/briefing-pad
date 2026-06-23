import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SessionViewModel
    private let keychainService: KeychainServiceProtocol

    @MainActor
    init(keychainService: KeychainServiceProtocol) {
        self.keychainService = keychainService
        let llmService = OpenAILLMService(keychainService: keychainService)
        let transcriptionService = SpeechTranscriptionService()

        let notionService: NotionServiceProtocol
        let notionToken = keychainService.load(key: KeychainKeys.notionIntegrationToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !notionToken.isEmpty {
            let client = NotionClient(token: notionToken)
            notionService = NotionService(client: client)
        } else {
            notionService = DisabledNotionService()
        }

        _viewModel = StateObject(wrappedValue: SessionViewModel(
            llmService: llmService,
            notionService: notionService,
            transcriptionService: transcriptionService
        ))
    }

    @MainActor
    init() {
        self.init(keychainService: KeychainService())
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
                            selectedPartIndex: viewModel.currentPartIndex,
                            onSelect: { index in
                                viewModel.selectPart(index: index)
                            }
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
                                generationError: part.aiMemoGenerationError,
                                isFinalizing: viewModel.isFinalizing,
                                isGenerating: viewModel.isGeneratingAIMemo,
                                syncStatus: viewModel.notionSyncStatuses[part.id] ?? .idle,
                                onRetry: { viewModel.retryNotionSync() },
                                onRegenerate: { viewModel.regenerateAIMemo() }
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

@MainActor
struct ContentView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        ContentView()
    }
}
