import Foundation
import Combine

class SessionViewModel: ObservableObject {
    @Published var sessions: [BriefingSession]
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false
    @Published var isFinalizing = false
    @Published var sessionState = SessionState()
    @Published var transcriptionError: String?

    @Published var micStatus: MicrophoneStatus = .idle
    @Published var audioLevel: AudioLevel = .silent
    @Published var partElapsedTime: TimeInterval = 0

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol
    private let transcriptionService: SpeechTranscribing
    private let micService: MicrophoneService
    private let clock: Clock

    private var transcriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?

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
        micService: MicrophoneService = MicrophoneService(),
        clock: Clock = RealClock(),
        scheduler: Scheduler = RealScheduler()
    ) {
        let loadedSessions = LocalBriefingDataStore.loadSessions()
        self.sessions = loadedSessions
        self.selectedSessionId = loadedSessions.first?.id ?? ""
        self.llmService = llmService
        self.notionService = notionService
        self.transcriptionService = transcriptionService
        self.micService = micService
        self.clock = clock

        self.chunker = TranscriptChunker(clock: clock, scheduler: scheduler) { [weak self] chunk in
            guard let self = self else { return }
            Task { @MainActor in
                await self.enqueueChunk(chunk)
            }
        }

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        micService.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.micStatus = status
                if status == .recording {
                    self.startTranscription(audioStream: self.micService.createAudioBufferStream())
                    self.startTimer()
                } else {
                    self.stopTranscription()
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)

        micService.$audioLevel
            .receive(on: RunLoop.main)
            .assign(to: \.audioLevel, on: self)
            .store(in: &cancellables)
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
            // 1. LLM Analysis
            let fullTranscript = (sessionState.partStates[part.id]?.transcript ?? [])
                .filter { $0.isFinal }
                .map { $0.text }
                .joined(separator: "\n")

            let result = try await llmService.analyzeTranscript(
                fullTranscript: fullTranscript,
                newChunk: chunk.text,
                partInfo: part
            )

            // 2. Merge Results into analysisState
            var updatedPart = part
            let now = clock.now

            updatedPart.analysisState.observationItemStates = mergeMatches(
                existingStates: part.analysisState.observationItemStates,
                matches: result.observationMatches,
                now: now
            )
            updatedPart.analysisState.positiveItemStates = mergeMatches(
                existingStates: part.analysisState.positiveItemStates,
                matches: result.positiveMatches,
                now: now
            )

            // Update local state immediately for UI responsiveness
            self.updateLocalPart(updatedPart, sessionId: sessionId, partIndex: partIndex)

            // 3. Notion Update (Disabled in Phase 4)
            /*
            if let blockId = updatedPart.aiMemoBlockId {
                // ...
            }
            */
        } catch {
            print("Failed to process chunk: \(error)")
            // Mark as failed in queue if we had a way to show it, but for now we just remove it.
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
        if micStatus == .recording || micStatus == .starting {
            let oldPartId = currentPart?.id
            let oldSessionId = selectedSessionId

            if micStatus == .starting {
                micService.cancelPendingOperationsAndStop()
            } else {
                micService.stopRecording()
            }
            stopTranscription(sessionId: oldSessionId, partId: oldPartId)
        }
        chunker?.flush()
        selectedSessionId = id
        currentPartIndex = 0
        transcriptionError = nil
        if let partId = currentPart?.id {
            partElapsedTime = sessionState.partStates[partId]?.elapsedTime ?? 0
        } else {
            partElapsedTime = 0
        }
    }

    // MARK: - Recording Operations

    func startRecording() {
        guard let partId = currentPart?.id else { return }
        let isFinished = sessionState.partStates[partId]?.isFinished ?? false
        guard !isFinished else { return }

        micService.startRecording()
    }

    func pauseRecording() {
        micService.stopRecording()
    }

    @MainActor
    func finishPart() async {
        guard !isFinalizing else { return }
        guard let part = currentPart else { return }

        let targetSessionId = selectedSessionId
        let targetPartIndex = currentPartIndex

        isFinalizing = true

        // 1. Stop recording and flush
        micService.stopRecording()
        stopTranscription(sessionId: targetSessionId, partId: part.id)

        // 2. Wait for queue to settle
        while !chunkQueue.isEmpty || isProcessing {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        // 3. Finalization Processing
        let positives = getSummarizedItems(
            items: part.positiveItems,
            states: part.analysisState.positiveItemStates
        )
        let observations = getSummarizedItems(
            items: part.observationItems,
            states: part.analysisState.observationItemStates
        )

        var oneLiner: String? = nil
        let summarizedTextList = positives.map { "良: \($0.text)" } + observations.map { "観: \($0.text)" }

        if !summarizedTextList.isEmpty {
            do {
                oneLiner = try await llmService.generateOneLiner(summarizedPoints: summarizedTextList)
            } catch {
                print("Failed to generate one-liner: \(error)")
                // Continue with deterministic part
            }
        }

        let finalMemo = formatFinalMemo(
            positives: positives,
            observations: observations,
            oneLiner: oneLiner
        )

        // 4. Update local state
        var updatedPart = part
        updatedPart.aiMemo = finalMemo
        updateLocalPart(updatedPart, sessionId: targetSessionId, partIndex: targetPartIndex)

        // 5. Notion Update
        if let blockId = updatedPart.aiMemoBlockId {
            do {
                _ = try await notionService.upsertAIMemo(blockId: blockId, content: finalMemo)
            } catch {
                print("Failed to update Notion: \(error)")
            }
        }

        // 6. Mark as finished
        var partState = sessionState.partStates[part.id] ?? PartState()
        partState.isFinished = true
        sessionState.partStates[part.id] = partState

        isFinalizing = false
    }

    func moveToNextPart() {
        selectPart(index: currentPartIndex + 1)
    }

    func moveToPreviousPart() {
        selectPart(index: currentPartIndex - 1)
    }

    func selectPart(index: Int) {
        guard let session = selectedSession,
              index >= 0,
              index < session.parts.count else { return }

        if micStatus == .recording || micStatus == .starting {
            let oldPartId = currentPart?.id
            let oldSessionId = selectedSessionId

            if micStatus == .starting {
                micService.cancelPendingOperationsAndStop()
            } else {
                micService.stopRecording()
            }
            stopTranscription(sessionId: oldSessionId, partId: oldPartId)
        }

        chunker?.flush()
        currentPartIndex = index
        let partId = session.parts[index].id
        partElapsedTime = sessionState.partStates[partId]?.elapsedTime ?? 0
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.incrementTimer()
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func incrementTimer() {
        partElapsedTime += 1
        if let partId = currentPart?.id {
            var partState = sessionState.partStates[partId] ?? PartState()
            partState.elapsedTime = partElapsedTime
            sessionState.partStates[partId] = partState
        }
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
    func stopTranscription(sessionId: String? = nil, partId: String? = nil) {
        let targetPartId = partId ?? currentPart?.id
        let targetSessionId = sessionId ?? selectedSessionId

        Task {
            await transcriptionService.stopTranscription()
            chunker?.flush()

            // Finalize remaining provisional segments as final
            if let partId = targetPartId {
                let segments = sessionState.partStates[partId]?.transcript ?? []
                var updatedSegments = segments
                var hasChanges = false
                for i in 0..<updatedSegments.count {
                    if !updatedSegments[i].isFinal {
                        let finalSegment = TranscriptSegment(
                            id: updatedSegments[i].id,
                            sessionId: targetSessionId,
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

    private func mergeMatches(
        existingStates: [String: AnalysisItemState],
        matches: [ItemMatch],
        now: Date
    ) -> [String: AnalysisItemState] {
        var newStates = existingStates
        for match in matches {
            let existing = newStates[match.itemId] ?? existingStates[match.itemId] ?? .hidden(at: now)

            // Merging logic:
            // 1. Higher confidence priority
            // 2. strong is sticky unless explicitly downgraded (confidence < 0.6)

            let newStatus: AnalysisItemStatus
            if match.confidence >= 0.8 {
                newStatus = .strong
            } else if match.confidence >= 0.6 {
                newStatus = .candidate
            } else {
                newStatus = .hidden
            }

            var shouldUpdate = false

            // Priority rules:
            // 1. Higher status wins (strong > candidate > hidden)
            // 2. Same status: higher confidence wins
            // 3. Special sticky rules for strong/candidate:
            //    - If existing is strong, only downgrade if new confidence is below 0.6 (explicit downgrade)
            //    - If existing is candidate, only downgrade to hidden if new confidence is very low (e.g. < 0.3)

            if newStatus > existing.status {
                // Upgrade
                shouldUpdate = true
            } else if newStatus == existing.status {
                // Same status, update if confidence improved
                if match.confidence > existing.confidence {
                    shouldUpdate = true
                }
            } else {
                // Potential downgrade
                if existing.status == .strong && match.confidence < 0.6 {
                    // strong -> candidate or hidden (explicit)
                    shouldUpdate = true
                } else if existing.status == .candidate && match.confidence < 0.3 {
                    // candidate -> hidden (explicit)
                    shouldUpdate = true
                }
            }

            if shouldUpdate {
                newStates[match.itemId] = AnalysisItemState(
                    confidence: match.confidence,
                    shortEvidence: match.shortEvidence,
                    status: newStatus,
                    lastUpdatedAt: now
                )
            }
        }
        return newStates
    }

    // MARK: - Finalization Logic

    struct SummarizedItem {
        let text: String
        let evidence: String
    }

    func getSummarizedItems<T: SummaryItemProtocol>(
        items: [T],
        states: [String: AnalysisItemState]
    ) -> [SummarizedItem] {
        struct SortableItem {
            let text: String
            let state: AnalysisItemState
        }

        var sortableItems: [SortableItem] = []

        for item in items {
            if let state = states[item.id], state.status != .hidden {
                sortableItems.append(SortableItem(text: item.text, state: state))
            }
        }

        return sortableItems
            .sorted { (a, b) -> Bool in
                if a.state.status != b.state.status {
                    return a.state.status > b.state.status
                }
                return a.state.confidence > b.state.confidence
            }
            .prefix(2)
            .map { SummarizedItem(text: $0.text, evidence: $0.state.shortEvidence) }
    }

    func formatFinalMemo(
        positives: [SummarizedItem],
        observations: [SummarizedItem],
        oneLiner: String?
    ) -> String {
        var lines: [String] = []

        if !positives.isEmpty {
            lines.append("◎ 短評で使えそう")
            for item in positives {
                lines.append("- \(item.text): \(item.evidence)")
            }
            lines.append("")
        }

        if !observations.isEmpty {
            lines.append("👀 根拠になりそうな観察")
            for item in observations {
                lines.append("- \(item.text): \(item.evidence)")
            }
            lines.append("")
        }

        if let oneLiner = oneLiner, !oneLiner.isEmpty {
            lines.append("💡 言えそうな一言")
            lines.append(oneLiner)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
