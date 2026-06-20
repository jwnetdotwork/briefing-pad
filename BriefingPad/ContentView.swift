import SwiftUI

struct ContentView: View {
    @State private var sessions = Session.dummySessions
    @State private var selectedSessionId: UUID?
    @State private var currentPartIndex: Int = 0
    @State private var isRecording: Bool = false

    init() {
        _selectedSessionId = State(initialValue: Session.dummySessions.first?.id)
    }

    var selectedSession: Session? {
        sessions.first(where: { $0.id == selectedSessionId })
    }

    var currentPart: Part? {
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
                    if let part = currentPart {
                        PartHeaderView(part: part)

                        Divider()
                            .padding(.horizontal)

                        PartControlsView(
                            currentPartIndex: $currentPartIndex,
                            totalParts: selectedSession?.parts.count ?? 0,
                            isRecording: $isRecording
                        )

                        Divider()
                            .padding(.horizontal)

                        TranscriptView(text: part.transcription)

                        ObservationPointsView(points: part.observationPoints)

                        GoodPointsView(points: part.goodPoints)

                        CommentMaterialView(aiMemo: part.aiMemo)
                    } else {
                        Text("セッションまたはパートが見つかりません")
                            .padding()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onChange(of: selectedSessionId) {
            currentPartIndex = 0
            isRecording = false
        }
    }
}

#Preview {
    ContentView()
}
