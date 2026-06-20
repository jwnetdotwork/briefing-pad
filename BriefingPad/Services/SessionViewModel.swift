import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [BriefingSession]
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false
    @Published var sessionState = SessionState()
    @Published var transcriptionError: String?

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol
    private let transcriptionService: SpeechTranscribing
    private let clock: Clock

    private var transcriptionTask: Task<Void, Never>?

    enum ChunkStatus: Equatable {
        case pending
        case sending
        case success
        case failed(String)
    }

    private struct QueuedChunk: Identifiable {
        let id: UUID
        let chunk: TranscriptChunk
        let sessionId: String
        let partIndex: Int
        var status: ChunkStatus
    }
    private var chunkQueue: [QueuedChunk] = []

    private var chunker: TranscriptChunker?

    init(
        llmService: LLMServiceProtocol = MockLLMService(),
        notionService: NotionServiceProtocol = MockNotionService(),
        transcriptionService: SpeechTranscribing = MockSpeechTranscriptionService(),
        clock: Clock = RealClock(),
        scheduler: Scheduler = RealScheduler()
    ) {
        let loadedSessions = LocalBriefingDataStore.loadSessions()
        self.sessions = loadedSessions
        self.selectedSessionId = loadedSessions.first?.id ?? ""
        self.llmService = llmService
        self.notionService = notionService
        self.transcriptionService = transcriptionService
        self.clock = clock

        self.chunker = TranscriptChunker(clock: clock, scheduler: scheduler) { [weak self] chunk in
            guard let self = self else { return }
            Task { @MainActor in
                await self.enqueueChunk(chunk)
            }
        }
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
    private func enqueueChunk(
        _ chunk: TranscriptChunk,
        sessionId: String? = nil,
        partIndex: Int? = nil
    ) async {
        let targetSessionId = sessionId ?? selectedSessionId
        let targetPartIndex: Int
        if let partIndex = partIndex {
            targetPartIndex = partIndex
        } else if let session = sessions.first(where: { $0.id == targetSessionId }),
                  let index = session.parts.firstIndex(where: { $0.id == chunk.partId }) {
            targetPartIndex = index
        } else {
            targetPartIndex = currentPartIndex
        }

        let queuedChunk = QueuedChunk(
            id: UUID(),
            chunk: chunk,
            sessionId: targetSessionId,
            partIndex: targetPartIndex,
            status: .pending
        )
        chunkQueue.append(queuedChunk)
        await processNextInQueue()
    }

    @MainActor
    private func processNextInQueue() async {
        guard !isProcessing else { return }

        isProcessing = true
        while !chunkQueue.isEmpty {
            await performProcessChunk()
        }
        isProcessing = false
    }

    @MainActor
    private func performProcessChunk() async {
        guard !chunkQueue.isEmpty else { return }
        var queuedChunk = chunkQueue[0]
        queuedChunk.status = .sending
        chunkQueue[0] = queuedChunk

        let sessionId = queuedChunk.sessionId
        let partIndex = queuedChunk.partIndex
        let chunk = queuedChunk.chunk

        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
              partIndex < sessions[sessionIndex].parts.count else {
            if !chunkQueue.isEmpty {
                chunkQueue.removeFirst()
            }
            return
        }

        let part = sessions[sessionIndex].parts[partIndex]

        do {
            // 1. LLM Update
            let updatedMemo = try await llmService.updateAIMemo(
                existingMemo: part.aiMemo,
                newTranscriptChunk: chunk.text,
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
        // Always remove the chunk after processing attempt to keep the queue bounded.
        // In Phase 3, we don't have automatic retries, so we just move on.
        if !chunkQueue.isEmpty {
            chunkQueue.removeFirst()
        }
    }

    private func updateLocalPart(_ updatedPart: PartDefinition, sessionId: String, partIndex: Int) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
              partIndex < sessions[sessionIndex].parts.count else { return }

        sessions[sessionIndex].parts[partIndex] = updatedPart
    }

    func selectSession(id: String) {
        chunker?.flush()
        selectedSessionId = id
        currentPartIndex = 0
        transcriptionError = nil
    }

    @MainActor
    func startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer>) {
        transcriptionError = nil
        transcriptionTask?.cancel()

        transcriptionTask = Task {
            do {
                await transcriptionService.stopTranscription()
                try await transcriptionService.startTranscription(audioStream: audioStream)

                for await segment in transcriptionService.results {
                    let segmentWithContext = TranscriptSegment(
                        id: segment.id,
                        sessionId: selectedSessionId,
                        partId: currentPart?.id ?? "",
                        text: segment.text,
                        isFinal: segment.isFinal,
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        receivedAt: segment.receivedAt
                    )
                    await handleTranscriptSegment(segmentWithContext)
                }
            } catch {
                self.transcriptionError = error.localizedDescription
            }
        }
    }

    @MainActor
    func stopTranscription() {
        let partId = currentPart?.id
        let sessionId = selectedSessionId
        let partIndex = currentPartIndex

        Task {
            await transcriptionService.stopTranscription()
            chunker?.flush()

            // Finalize remaining provisional segments as final
            if let partId = partId {
                let segments = sessionState.partStates[partId]?.transcript ?? []
                var updatedSegments = segments
                var hasChanges = false
                for i in 0..<updatedSegments.count {
                    if !updatedSegments[i].isFinal {
                        let finalSegment = TranscriptSegment(
                            id: updatedSegments[i].id,
                            sessionId: sessionId,
                            partId: partId,
                            text: updatedSegments[i].text,
                            isFinal: true,
                            startTime: updatedSegments[i].startTime,
                            endTime: updatedSegments[i].endTime,
                            receivedAt: updatedSegments[i].receivedAt
                        )
                        updatedSegments[i] = finalSegment
                        hasChanges = true
                        chunker?.processSegment(finalSegment)
                    }
                }
                if hasChanges {
                    sessionState.partStates[partId]?.transcript = updatedSegments
                    chunker?.flush()
                }
            }
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    @MainActor
    func handleTranscriptSegment(_ segment: TranscriptSegment) async {
        let partId = segment.partId
        guard !partId.isEmpty else { return }

        var partState = sessionState.partStates[partId] ?? PartState()

        if let index = partState.transcript.firstIndex(where: { $0.id == segment.id }) {
            // Update existing segment
            let wasFinal = partState.transcript[index].isFinal
            partState.transcript[index] = segment

            // Only process if it just became final
            if segment.isFinal && !wasFinal {
                chunker?.processSegment(segment)
            }
        } else {
            // Append new segment
            partState.transcript.append(segment)

            if segment.isFinal {
                chunker?.processSegment(segment)
            }
        }

        sessionState.partStates[partId] = partState
    }

    // For debugging and manual injection (legacy support)
    @MainActor
    func processTranscriptChunk(
        _ text: String,
        sessionId: String? = nil,
        partIndex: Int? = nil
    ) async {
        let targetPartId = currentPart?.id ?? ""
        let now = clock.now.timeIntervalSince1970
        let chunk = TranscriptChunk(
            partId: targetPartId,
            text: text,
            startTime: now,
            endTime: now
        )
        await enqueueChunk(chunk, sessionId: sessionId, partIndex: partIndex)
    }
}
