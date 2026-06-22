import Foundation
import Combine
import CryptoKit
import AVFoundation

@MainActor
class SessionViewModel: ObservableObject {
    @Published var sessions: [BriefingSession]
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false
    @Published var isFinalizing = false
    @Published var sessionState = SessionState()
    @Published var transcriptionError: String?

    enum NotionSyncStatus: Equatable {
        case idle
        case writing
        case success
        case externalModification
        case failure(String)
        case noToken
    }
    @Published var notionSyncStatuses: [String: NotionSyncStatus] = [:] // partId -> status

    @Published var micStatus: MicrophoneStatus = .idle
    @Published var audioLevel: AudioLevel = .silent
    @Published var partElapsedTime: TimeInterval = 0

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol
    private let transcriptionService: SpeechTranscribing
    private let micService: MicrophoneService
    private let store: SessionStoreProtocol
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

    private struct RecordingContext: Equatable {
        let sessionId: String
        let partId: String
    }
    @Published private var activeRecordingContext: RecordingContext?

    init(
        llmService: LLMServiceProtocol = MockLLMService(),
        notionService: NotionServiceProtocol = MockNotionService(),
        transcriptionService: SpeechTranscribing = MockSpeechTranscriptionService(),
        micService: MicrophoneService = MicrophoneService(),
        store: SessionStoreProtocol = FileSessionStore(),
        clock: Clock = RealClock(),
        scheduler: Scheduler? = nil
    ) {
        let loadedSessions = LocalBriefingDataStore.loadSessions()
        self.sessions = loadedSessions
        self.selectedSessionId = loadedSessions.first?.id ?? ""
        self.llmService = llmService
        self.notionService = notionService
        self.transcriptionService = transcriptionService
        self.micService = micService
        self.store = store
        self.clock = clock

        self.chunker = TranscriptChunker(clock: clock, scheduler: scheduler ?? RealScheduler()) { [weak self] chunk in
            guard let self = self else { return }
            Task { @MainActor in
                await self.enqueueChunk(chunk)
            }
        }

        setupSubscriptions()

        Task {
            await loadSavedSessionsFromStore()
            await loadSavedSession()
        }
    }

    @MainActor
    private func loadSavedSessionsFromStore() async {
        let currentSessionIds = Set(sessions.map { $0.id })

        // Execute I/O on background thread
        let loadedTemplates = await Task.detached(priority: .background) { [store] in
            var results: [BriefingSession] = []
            do {
                let sessionIds = try await store.listSessions()
                for id in sessionIds {
                    if !currentSessionIds.contains(id) {
                        do {
                            if let saved = try await store.loadSession(sessionId: id) {
                                results.append(saved.templateSnapshot)
                            }
                        } catch {
                            print("Failed to load session \(id): \(error)")
                        }
                    }
                }
            } catch {
                print("Failed to list sessions: \(error)")
            }
            return results
        }.value

        // Apply results on main thread
        for template in loadedTemplates {
            if !sessions.contains(where: { $0.id == template.id }) {
                sessions.append(template)
            }
        }
    }

    func importNotionSession(_ session: BriefingSession, notionPageId: String) {
        sessions.append(session)
        self.notionPageId = notionPageId
        self.selectedSessionId = session.id
        self.currentPartIndex = 0
        self.sessionState = SessionState()
        saveCurrentSession()
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
                    Task {
                        await self.stopTranscription()
                    }
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

            // Record LLM Result
            let llmResult = LLMResult(
                observationMatches: result.observationMatches,
                positiveMatches: result.positiveMatches,
                sourceChunkId: chunk.id,
                sourceChunkText: chunk.text,
                sourceChunkStartTime: chunk.startTime,
                sourceChunkEndTime: chunk.endTime
            )
            sessionState.partStates[part.id]?.llmResults.append(llmResult)

            saveCurrentSession()

            // 3. Notion Update
            if let blockId = updatedPart.aiMemoBlockId {
                let finalMemo = formatFinalMemo(
                    positives: getSummarizedItems(items: updatedPart.positiveItems, states: updatedPart.analysisState.positiveItemStates),
                    observations: getSummarizedItems(items: updatedPart.observationItems, states: updatedPart.analysisState.observationItemStates),
                    oneLiner: nil // Don't include one-liner in live updates
                )
                triggerNotionSync(blockId: blockId, content: finalMemo, partId: part.id)
            }
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
        let oldPartId = currentPart?.id
        let oldSessionId = selectedSessionId

        if micStatus == .recording || micStatus == .starting {
            if micStatus == .starting {
                micService.cancelPendingOperationsAndStop()
            } else {
                micService.stopRecording()
            }
            Task {
                await stopTranscription(sessionId: oldSessionId, partId: oldPartId)
            }
        } else {
            // Not recording, but should still flush
            chunker?.flush()
        }

        selectedSessionId = id
        currentPartIndex = 0
        transcriptionError = nil
        partElapsedTime = 0

        Task {
            await loadSavedSession()
        }
    }

    private var notionPageId: String?

    @MainActor
    private func loadSavedSession() async {
        do {
            if let saved = try await store.loadSession(sessionId: selectedSessionId) {
                self.notionPageId = saved.notionPageId
                // Restore template snapshot (parts, analysisState, etc)
                if let index = sessions.firstIndex(where: { $0.id == selectedSessionId }) {
                    sessions[index] = saved.templateSnapshot
                }

                // Restore SessionState
                var newState = SessionState()
                for (partId, partRun) in saved.partRuns {
                    newState.partStates[partId] = PartState(
                        transcript: partRun.transcript,
                        isFinished: partRun.isFinished,
                        elapsedTime: partRun.elapsedTime,
                        llmResults: partRun.llmResults,
                        finalSummary: partRun.finalSummary,
                        audioFileName: partRun.audioFileName
                    )
                }
                self.sessionState = newState
            } else {
                // If no saved session, reset sessionState for this session
                self.sessionState = SessionState()
                // Also reset parts to initial state if needed,
                // but since we load them from LocalBriefingDataStore in init,
                // we might want to re-load the template if it was modified.
                let templates = LocalBriefingDataStore.loadSessions()
                if let template = templates.first(where: { $0.id == selectedSessionId }),
                   let index = sessions.firstIndex(where: { $0.id == selectedSessionId }) {
                    sessions[index] = template
                }
            }

            if let partId = currentPart?.id {
                partElapsedTime = sessionState.partStates[partId]?.elapsedTime ?? 0
            } else {
                partElapsedTime = 0
            }
        } catch {
            print("Failed to load saved session: \(error)")
        }
    }

    func saveCurrentSession() {
        guard let session = selectedSession else { return }

        var partRuns: [String: PartRun] = [:]
        for (partId, partState) in sessionState.partStates {
            var partRun = PartRun(partId: partId)
            partRun.transcript = partState.transcript
            partRun.elapsedTime = partState.elapsedTime
            partRun.isFinished = partState.isFinished
            partRun.llmResults = partState.llmResults
            partRun.finalSummary = partState.finalSummary
            partRun.audioFileName = partState.audioFileName

            partRuns[partId] = partRun
        }

        let saved = SavedSession(
            sessionId: selectedSessionId,
            templateSnapshot: session,
            updatedAt: clock.now,
            notionPageId: notionPageId,
            errorHistory: [],
            partRuns: partRuns
        )

        Task {
            await enqueueSave(saved)
        }
    }

    private var activeSaveTask: Task<Void, Never>?
    private var pendingSave: SavedSession?

    private var notionSyncTask: Task<Void, Never>?
    private var pendingAIMemoUpdate: String?

    @MainActor
    private func enqueueSave(_ session: SavedSession) async {
        pendingSave = session

        guard activeSaveTask == nil else { return }

        activeSaveTask = Task {
            while let sessionToSave = pendingSave {
                pendingSave = nil
                do {
                    try await store.saveSession(sessionToSave)
                } catch {
                    print("Failed to save session: \(error)")
                }
            }
            activeSaveTask = nil
        }
    }

    func deleteCurrentSession() {
        Task {
            do {
                try await store.deleteSession(sessionId: selectedSessionId)
                await loadSavedSession() // Reload to template state
            } catch {
                print("Failed to delete session: \(error)")
            }
        }
    }

    func deleteCurrentPartData(onlyAudio: Bool = false, onlyTranscript: Bool = false, onlyLLM: Bool = false) {
        guard let partId = currentPart?.id else { return }

        Task { @MainActor in
            // Stop recording/transcription if active for THIS part
            if micStatus == .recording || micStatus == .starting {
                await stopTranscription()
                micService.stopRecording()
            }

            do {
                if !onlyAudio && !onlyTranscript && !onlyLLM {
                    // Delete all for this part
                    try await store.deleteAudio(sessionId: selectedSessionId, partId: partId)
                    try await store.deleteTranscript(sessionId: selectedSessionId, partId: partId)
                    try await store.deleteLLMResults(sessionId: selectedSessionId, partId: partId)

                    // Reset local state for this part
                    sessionState.partStates[partId] = PartState()
                    // Also reset part definition in session
                    if let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
                       let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == partId }) {
                        let templates = LocalBriefingDataStore.loadSessions()
                        if let templateSession = templates.first(where: { $0.id == selectedSessionId }),
                           let templatePart = templateSession.parts.first(where: { $0.id == partId }) {
                            sessions[sessionIndex].parts[partIndex] = templatePart
                        }
                    }
                } else {
                    if onlyAudio {
                        try await store.deleteAudio(sessionId: selectedSessionId, partId: partId)
                        sessionState.partStates[partId]?.audioFileName = nil
                    }
                    if onlyTranscript {
                        try await store.deleteTranscript(sessionId: selectedSessionId, partId: partId)
                        sessionState.partStates[partId]?.transcript = []
                        chunker?.flush()
                    }
                    if onlyLLM {
                        try await store.deleteLLMResults(sessionId: selectedSessionId, partId: partId)
                        sessionState.partStates[partId]?.llmResults = []
                        sessionState.partStates[partId]?.finalSummary = nil

                        // Reset analysis state in PartDefinition
                        if let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
                           let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == partId }) {
                            let part = sessions[sessionIndex].parts[partIndex]
                            sessions[sessionIndex].parts[partIndex].analysisState = PartAnalysisState.initial(
                                observationItems: part.observationItems,
                                positiveItems: part.positiveItems
                            )
                            sessions[sessionIndex].parts[partIndex].aiMemo = ""
                        }
                    }
                }
                saveCurrentSession()
            } catch {
                print("Failed to delete part data: \(error)")
            }
        }
    }

    // MARK: - Recording Operations

    func startRecording() {
        guard let partId = currentPart?.id else { return }
        let isFinished = sessionState.partStates[partId]?.isFinished ?? false
        guard !isFinished else { return }

        let recordingId = UUID().uuidString
        let audioURL = store.getAudioURL(sessionId: selectedSessionId, partId: partId, recordingId: recordingId)

        // Update local state to track this audio file
        var partState = sessionState.partStates[partId] ?? PartState()
        partState.audioFileName = audioURL.lastPathComponent
        sessionState.partStates[partId] = partState

        micService.startRecording(audioFileURL: audioURL)
    }

    func pauseRecording() {
        Task {
            await stopTranscription() // This ensures segments are finalized
            micService.stopRecording()
            saveCurrentSession()
        }
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
        await stopTranscription(sessionId: targetSessionId, partId: part.id)

        // 2. Wait for queue to settle
        while !chunkQueue.isEmpty || isProcessing {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        // 3. Finalization Processing
        // Re-fetch part after wait to get latest analysis results
        guard let session = sessions.first(where: { $0.id == targetSessionId }),
              targetPartIndex < session.parts.count else {
            isFinalizing = false
            return
        }
        let latestPart = session.parts[targetPartIndex]

        let positives = getSummarizedItems(
            items: latestPart.positiveItems,
            states: latestPart.analysisState.positiveItemStates
        )
        let observations = getSummarizedItems(
            items: latestPart.observationItems,
            states: latestPart.analysisState.observationItemStates
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
        var updatedPart = latestPart
        updatedPart.aiMemo = finalMemo
        updateLocalPart(updatedPart, sessionId: targetSessionId, partIndex: targetPartIndex)

        // Record Final Summary
        let finalSummary = FinalSummary(
            text: finalMemo,
            adoptedItemIds: positives.map { $0.text } + observations.map { $0.text },
            sourceLLMResultIds: sessionState.partStates[part.id]?.llmResults.map { $0.id } ?? []
        )
        sessionState.partStates[part.id]?.finalSummary = finalSummary

        // 5. Notion Update (Wait for final sync)
        if let blockId = updatedPart.aiMemoBlockId {
            await syncNotionImmediately(blockId: blockId, content: finalMemo, partId: part.id)
        }

        // 6. Mark as finished
        var partState = sessionState.partStates[part.id] ?? PartState()
        partState.isFinished = true
        sessionState.partStates[part.id] = partState

        saveCurrentSession()
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

        let oldPartId = currentPart?.id
        let oldSessionId = selectedSessionId

        if micStatus == .recording || micStatus == .starting {
            if micStatus == .starting {
                micService.cancelPendingOperationsAndStop()
            } else {
                micService.stopRecording()
            }
            Task {
                await stopTranscription(sessionId: oldSessionId, partId: oldPartId)
            }
        } else {
            // Not recording, but should still flush
            chunker?.flush()
        }

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

        let context = RecordingContext(
            sessionId: selectedSessionId,
            partId: currentPart?.id ?? ""
        )
        activeRecordingContext = context

        transcriptionTask = Task {
            do {
                await transcriptionService.stopTranscription()
                try await transcriptionService.startTranscription(audioStream: audioStream)

                for await segment in transcriptionService.results {
                    // Only process segments if they match the context when they were received
                    guard let activeContext = self.activeRecordingContext,
                          activeContext == context else { continue }

                    let segmentWithContext = TranscriptSegment(
                        id: segment.id,
                        sessionId: context.sessionId,
                        partId: context.partId,
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
    func stopTranscription(sessionId: String? = nil, partId: String? = nil) async {
        let targetPartId = partId ?? activeRecordingContext?.partId ?? currentPart?.id
        let targetSessionId = sessionId ?? activeRecordingContext?.sessionId ?? selectedSessionId

        activeRecordingContext = nil

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

        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    // MARK: - Notion Sync logic

    func triggerNotionSync(blockId: String, content: String, partId: String) {
        pendingAIMemoUpdate = content

        guard notionSyncTask == nil else { return }

        notionSyncTask = Task { @MainActor in
            while let contentToSync = pendingAIMemoUpdate {
                // Throttle: if same content as last synced, skip
                if let session = selectedSession,
                   let part = session.parts.first(where: { $0.id == partId }),
                   part.lastSyncedHash == CryptoUtils.calculateHash(content: contentToSync) {
                    pendingAIMemoUpdate = nil
                    break
                }

                pendingAIMemoUpdate = nil
                await performNotionSync(blockId: blockId, content: contentToSync, partId: partId)
            }
            notionSyncTask = nil
        }
    }

    private func syncNotionImmediately(blockId: String, content: String, partId: String) async {
        pendingAIMemoUpdate = nil
        notionSyncTask?.cancel()
        notionSyncTask = nil
        await performNotionSync(blockId: blockId, content: content, partId: partId)
    }

    @MainActor
    private func performNotionSync(blockId: String, content: String, partId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
              let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == partId }) else { return }

        let part = sessions[sessionIndex].parts[partIndex]
        notionSyncStatuses[partId] = .writing

        do {
            let result = try await notionService.upsertAIMemo(
                blockId: blockId,
                content: content,
                expectedLastEditedTime: part.lastSyncedTime,
                expectedContentHash: part.lastSyncedHash
            )

            switch result {
            case .success(let time, let hash):
                sessions[sessionIndex].parts[partIndex].lastSyncedTime = time
                sessions[sessionIndex].parts[partIndex].lastSyncedHash = hash
                notionSyncStatuses[partId] = .success
            case .externalModification(let newBlockId, let time, let hash):
                sessions[sessionIndex].parts[partIndex].aiMemoBlockId = newBlockId
                sessions[sessionIndex].parts[partIndex].lastSyncedTime = time
                sessions[sessionIndex].parts[partIndex].lastSyncedHash = hash
                notionSyncStatuses[partId] = .externalModification
            case .failure(let error):
                notionSyncStatuses[partId] = .failure(error)
            case .noToken:
                notionSyncStatuses[partId] = .noToken
            }
            saveCurrentSession()
        } catch {
            notionSyncStatuses[partId] = .failure(error.localizedDescription)
        }
    }

    func retryNotionSync() {
        guard let part = currentPart, let blockId = part.aiMemoBlockId else { return }

        // Use the stored aiMemo which might already have one-liner if part was finished.
        // If empty, generate from current analysis.
        let content: String
        if part.aiMemo.isEmpty {
             content = formatFinalMemo(
                positives: getSummarizedItems(items: part.positiveItems, states: part.analysisState.positiveItemStates),
                observations: getSummarizedItems(items: part.observationItems, states: part.analysisState.observationItemStates),
                oneLiner: nil
            )
        } else {
            content = part.aiMemo
        }

        triggerNotionSync(blockId: blockId, content: content, partId: part.id)
    }

    @MainActor
    func handleTranscriptSegment(_ segment: TranscriptSegment) async {
        let partId = segment.partId
        guard !partId.isEmpty else { return }

        var partState = sessionState.partStates[partId] ?? PartState()

        var shouldSave = false
        if let index = partState.transcript.firstIndex(where: { $0.id == segment.id }) {
            // Update existing segment by ID (Standard case)
            let wasFinal = partState.transcript[index].isFinal
            partState.transcript[index] = segment

            // Only process if it just became final
            if segment.isFinal && !wasFinal {
                chunker?.processSegment(segment)
                shouldSave = true
            }
        } else if let duplicateIndex = findDuplicateIndex(for: segment, in: partState.transcript) {
            // Update existing segment by similarity
            let existing = partState.transcript[duplicateIndex]

            // Priority: Final over Provisional
            if segment.isFinal || !existing.isFinal {
                let wasFinal = existing.isFinal
                partState.transcript[duplicateIndex] = segment

                if segment.isFinal && !wasFinal {
                    chunker?.processSegment(segment)
                    shouldSave = true
                }
            }
        } else {
            // Append new segment
            partState.transcript.append(segment)

            if segment.isFinal {
                chunker?.processSegment(segment)
                shouldSave = true
            }
        }

        sessionState.partStates[partId] = partState
        if shouldSave {
            saveCurrentSession()
        }
    }

    private func findDuplicateIndex(for segment: TranscriptSegment, in transcript: [TranscriptSegment]) -> Int? {
        // Look backwards as duplicates are likely near the end
        for (index, existing) in transcript.enumerated().reversed() {
            // Time proximity: within 2 seconds
            let timeDiff = abs(segment.startTime - existing.startTime)
            if timeDiff < 2.0 {
                let text1 = normalizeForComparison(segment.text)
                let text2 = normalizeForComparison(existing.text)

                if text1 == text2 && !text1.isEmpty {
                    return index
                }
            }
        }
        return nil
    }

    private func normalizeForComparison(_ text: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        return text.components(separatedBy: punctuation).joined().lowercased()
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

private struct SortableItem {
    let text: String
    let state: AnalysisItemState
}
