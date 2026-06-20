import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [BriefingSession]
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol

    private struct QueuedChunk {
        let text: String
        let sessionId: String
        let partIndex: Int
    }
    private var chunkQueue: [QueuedChunk] = []

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
        let queuedChunk = QueuedChunk(
            text: chunk,
            sessionId: selectedSessionId,
            partIndex: currentPartIndex
        )
        chunkQueue.append(queuedChunk)
        guard !isProcessing else { return }

        isProcessing = true
        while !chunkQueue.isEmpty {
            let next = chunkQueue.removeFirst()
            await performProcessChunk(next)
        }
        isProcessing = false
    }

    @MainActor
    private func performProcessChunk(_ queuedChunk: QueuedChunk) async {
        let sessionId = queuedChunk.sessionId
        let partIndex = queuedChunk.partIndex
        let text = queuedChunk.text

        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
              partIndex < sessions[sessionIndex].parts.count else { return }

        let part = sessions[sessionIndex].parts[partIndex]

        do {
            // 1. LLM Update
            let updatedMemo = try await llmService.updateAIMemo(
                existingMemo: part.aiMemo,
                newTranscriptChunk: text,
                partInfo: part
            )

            // Update local state immediately for UI responsiveness
            var updatedPart = part
            updatedPart.aiMemo = updatedMemo
            self.updateLocalPart(updatedPart, sessionId: sessionId, partIndex: partIndex)

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
                    self.updateLocalPart(updatedPartWithNewId, sessionId: sessionId, partIndex: partIndex)
                case .failure(let error):
                    print("Notion update failed: \(error)")
                }
            }
        } catch {
            print("Failed to process chunk: \(error)")
        }
    }

    private func updateLocalPart(_ updatedPart: PartDefinition, sessionId: String, partIndex: Int) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
              partIndex < sessions[sessionIndex].parts.count else { return }

        sessions[sessionIndex].parts[partIndex] = updatedPart
    }

    func selectSession(id: String) {
        selectedSessionId = id
        currentPartIndex = 0
    }
}
