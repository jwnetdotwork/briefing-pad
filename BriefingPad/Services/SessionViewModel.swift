import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [BriefingSession]
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol

    init(
        llmService: LLMServiceProtocol = MockLLMService(),
        notionService: NotionServiceProtocol = MockNotionService()
    ) {
        let loadedSessions = LocalBriefingDataStore.loadSessions()
        self.sessions = loadedSessions
        self.selectedSessionId = loadedSessions.first?.id ?? ""
        self.llmService = llmService
        self.notionService = notionService
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

    @MainActor
    func processTranscriptChunk(_ chunk: String) async {
        guard let session = selectedSession,
              currentPartIndex < session.parts.count else { return }

        let part = session.parts[currentPartIndex]
        isProcessing = true

        do {
            // 1. LLM Update
            let updatedMemo = try await llmService.updateAIMemo(
                existingMemo: part.aiMemo,
                newTranscriptChunk: chunk,
                partInfo: part
            )

            // Update local state immediately for UI responsiveness
            var updatedPart = part
            updatedPart.aiMemo = updatedMemo
            self.updateLocalPart(updatedPart)

            // 2. Notion Update
            if let blockId = updatedPart.aiMemoBlockId {
                let result = try await notionService.upsertAIMemo(blockId: blockId, content: updatedMemo)

                switch result {
                case .success:
                    print("Notion updated successfully")
                case .externalModification(let newBlockId):
                    print("External modification detected, updated with new block ID: \(newBlockId)")
                    var updatedPartWithNewId = updatedPart
                    updatedPartWithNewId.aiMemoBlockId = newBlockId
                    self.updateLocalPart(updatedPartWithNewId)
                case .failure(let error):
                    print("Notion update failed: \(error)")
                }
            }
        } catch {
            print("Failed to process chunk: \(error)")
        }

        isProcessing = false
    }

    private func updateLocalPart(_ updatedPart: PartDefinition) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
              currentPartIndex < sessions[sessionIndex].parts.count else { return }

        sessions[sessionIndex].parts[currentPartIndex] = updatedPart
    }

    func selectSession(id: String) {
        selectedSessionId = id
        currentPartIndex = 0
    }
}
