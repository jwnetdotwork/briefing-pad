import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @StateObject private var micService = MicrophoneService()

    var body: some View {
        VStack(spacing: 0) {
            SessionToolbarView(
                selectedSessionId: $viewModel.selectedSessionId,
                sessions: viewModel.sessions
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

                                if micService.status == .recording {
                                    Button(action: {
                                        Task {
                                            await viewModel.processTranscriptChunk("新しい発言のチャンク \(Date().formatted(date: .omitted, time: .standard))")
                                        }
                                    }) {
                                        HStack {
                                            if viewModel.isProcessing {
                                                ProgressView()
                                                    .controlSize(.small)
                                            }
                                            Text("デバッグ: 確定チャンクをエミュレート")
                                        }
                                    }
                                    .disabled(viewModel.isProcessing)
                                    .padding(.bottom, 8)
                                }
                            }

                            Divider()
                                .padding(.horizontal)

                            TranscriptView(text: part.rawMarkdown)

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
