import SwiftUI

struct ContentView: View {
    @State private var sessions: [BriefingSession]
    @State private var selectedSessionId: String
    @State private var currentPartIndex: Int = 0
    @StateObject private var micService = MicrophoneService()

    init() {
        let loadedSessions = LocalBriefingDataStore.loadSessions()
        _sessions = State(initialValue: loadedSessions)
        _selectedSessionId = State(initialValue: loadedSessions.first?.id ?? "")
    }

    var selectedSession: BriefingSession? {
        sessions.first(where: { $0.id == selectedSessionId })
    }

    var currentPart: PartDefinition? {
        guard let session = selectedSession,
              currentPartIndex < session.parts.count else {
            return nil
        }
        return session.parts[currentPartIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionToolbarView(
                selectedSessionId: $selectedSessionId,
                sessions: sessions
            )

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if let session = selectedSession {
                        PartListView(
                            parts: session.parts,
                            selectedPartIndex: $currentPartIndex
                        )

                        if let part = currentPart {
                            PartHeaderView(part: part)

                            Divider()
                                .padding(.horizontal)

                            PartControlsView(
                                currentPartIndex: $currentPartIndex,
                                totalParts: session.parts.count,
                                micService: micService
                            )

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
        .onChange(of: selectedSessionId) {
            currentPartIndex = 0
            micService.stopRecording()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
