import Foundation
import Combine
import CryptoKit
import AVFoundation

@MainActor
class SessionViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var sessions: [BriefingSession]
    @Published var sortOrder: SessionSortOrder
    @Published var selectedSessionId: String
    @Published var currentPartIndex: Int = 0
    @Published var isProcessing = false
    @Published var isFinalizing = false
    @Published var isGeneratingAIMemo = false
    @Published var sessionState = SessionState()
    @Published var transcriptionError: String?
    @Published var selectedTranscriptionLocale: String = "ja-JP"
    @Published var supportedLocales: [Locale] = []
    private var hasPersistedLocale: Bool = false

    enum NotionSyncStatus: Equatable {
        case idle
        case writing
        case success
        case externalModification
        case failure(String)
        case noToken
    }
    @Published var notionSyncStatuses: [String: NotionSyncStatus] = [:] // partId -> status

    private static let lastSelectedSessionKey = "lastSelectedSessionId"
    static let selectedLocaleKey = "selectedTranscriptionLocale"
    private let userDefaults: UserDefaults

    @Published var micStatus: MicrophoneStatus = .idle
    @Published var audioLevel: AudioLevel = .silent
    @Published var audioAmplitude: Float = 0.0
    @Published var partElapsedTime: TimeInterval = 0

    @Published var isPlaying: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var playbackQueue: [URL] = []
    private var currentPlaybackIndex: Int = 0

    private let llmService: LLMServiceProtocol
    private let notionService: NotionServiceProtocol
    private let transcriptionService: SpeechTranscribing
    private let micService: any MicrophoneServiceProtocol
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
    @Published private(set) var isBootstrapped = false

    private var currentRunID: String?

    private func debugLog(_ event: String, extra: String? = nil) {
        #if DEBUG
        let runID = currentRunID ?? "none"
        let sessionId = selectedSessionId
        let partId = currentPart?.id ?? "none"
        let micStatusStr = "\(micStatus)"
        let contextStr = activeRecordingContext != nil ? "\(activeRecordingContext!.sessionId):\(activeRecordingContext!.partId)" : "nil"
        let transcriptCount = sessionState.partStates[partId]?.transcript.count ?? 0
        let queueCount = chunkQueue.count

        var message = "[SessionViewModel] [\(runID)] \(event) | sess: \(sessionId), part: \(partId), mic: \(micStatusStr), ctx: \(contextStr), transcript: \(transcriptCount), queue: \(queueCount)"
        if let extra = extra {
            message += " | \(extra)"
        }
        print(message)
        #endif
    }

    init(
        llmService: LLMServiceProtocol? = nil,
        notionService: NotionServiceProtocol? = nil,
        transcriptionService: SpeechTranscribing? = nil,
        micService: any MicrophoneServiceProtocol,
        store: SessionStoreProtocol? = nil,
        clock: Clock? = nil,
        scheduler: Scheduler? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.sessions = []
        self.userDefaults = userDefaults
        let sortOrderRaw = userDefaults.string(forKey: "sessionSortOrder") ?? SessionSortOrder.createdDesc.rawValue
        self.sortOrder = SessionSortOrder(rawValue: sortOrderRaw) ?? .createdDesc
        self.selectedSessionId = userDefaults.string(forKey: Self.lastSelectedSessionKey) ?? ""

        self.hasPersistedLocale = userDefaults.object(forKey: Self.selectedLocaleKey) != nil
        self.selectedTranscriptionLocale = userDefaults.string(forKey: Self.selectedLocaleKey) ?? "ja-JP"

        self.llmService = llmService ?? MockLLMService()
        self.notionService = notionService ?? MockNotionService()
        self.transcriptionService = transcriptionService ?? MockSpeechTranscriptionService()
        self.micService = micService
        self.store = store ?? FileSessionStore()
        self.clock = clock ?? RealClock()

        super.init()

        self.chunker = TranscriptChunker(clock: self.clock, scheduler: scheduler ?? RealScheduler(), onFlush: { [weak self] chunk in
            guard let self = self else { return }
            Task { @MainActor in
                await self.enqueueChunk(chunk)
            }
        })

        setupSubscriptions()

        Task {
            await loadSavedSessionsFromStore()
            await loadSavedSession()
            await loadSupportedLocales()
            isBootstrapped = true
        }
    }

    private func loadSupportedLocales() async {
        let locales = await transcriptionService.getSupportedLocales()
        self.supportedLocales = locales

        if hasPersistedLocale {
            // Validate current locale
            if !locales.contains(where: { $0.identifier == selectedTranscriptionLocale }) {
                if locales.contains(where: { $0.identifier == "ja-JP" }) {
                    selectedTranscriptionLocale = "ja-JP"
                } else {
                    selectedTranscriptionLocale = locales.first?.identifier ?? "ja-JP"
                }
                userDefaults.set(selectedTranscriptionLocale, forKey: Self.selectedLocaleKey)
            }
        } else {
            selectedTranscriptionLocale = resolveInitialLocale(
                supportedLocales: locales,
                preferredIdentifiers: Locale.preferredLanguages
            )
        }
    }

    internal func resolveInitialLocale(supportedLocales: [Locale], preferredIdentifiers: [String]) -> String {

        // 1. Exact identifier match
        for pref in preferredIdentifiers {
            if let match = supportedLocales.first(where: { $0.identifier == pref }) {
                return match.identifier
            }
        }

        // 2. Language-code match
        for pref in preferredIdentifiers {
            let prefLocale = Locale(identifier: pref)
            let prefLang = prefLocale.language.languageCode?.identifier

            guard let prefLang = prefLang else { continue }

            if let match = supportedLocales.first(where: { $0.language.languageCode?.identifier == prefLang }) {
                return match.identifier
            }
        }

        // 3. Fallback to ja-JP
        if supportedLocales.contains(where: { $0.identifier == "ja-JP" }) {
            return "ja-JP"
        }

        // 4. First supported locale
        return supportedLocales.first?.identifier ?? "ja-JP"
    }

    func updateTranscriptionLocale(_ identifier: String) {
        selectedTranscriptionLocale = identifier
        userDefaults.set(selectedTranscriptionLocale, forKey: Self.selectedLocaleKey)
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

        if !selectedSessionId.isEmpty && !sessions.contains(where: { $0.id == selectedSessionId }) {
            selectedSessionId = ""
        }

        if selectedSessionId.isEmpty {
            selectedSessionId = sessions.first?.id ?? ""
            currentPartIndex = 0
            userDefaults.set(selectedSessionId, forKey: Self.lastSelectedSessionKey)
        }
    }

    func importNotionSession(_ session: BriefingSession, notionPageId: String) {
        activateSession(session, notionPageId: notionPageId)
    }

    func createEmptySession(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let now = clock.now
        let session = BriefingSession(
            id: UUID().uuidString,
            name: trimmedName,
            parts: [],
            createdAt: now,
            updatedAt: now
        )
        activateSession(session, notionPageId: nil)
    }

    func updateSessionName(id: String, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = trimmedName
        saveCurrentSession()
    }

    func addManualPart(
        number: Int?,
        title: String,
        durationMinutes: Int?,
        setting: String?,
        learningPointsText: String,
        observationItemsText: String,
        positiveItemsText: String
    ) {
        stopPlayback()
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }) else { return }

        let nextNumber = (sessions[sessionIndex].parts.map { $0.number }.max() ?? 0) + 1
        let finalNumber = number ?? nextNumber

        let learningPoints = parseLinesToItems(learningPointsText) { text in
            LearningPoint(id: UUID().uuidString, text: text)
        }
        let observationItems = parseLinesToItems(observationItemsText) { text in
            ObservationItem(id: UUID().uuidString, text: text)
        }
        let positiveItems = parseLinesToItems(positiveItemsText) { text in
            PositiveItem(id: UUID().uuidString, text: text)
        }

        let newPart = PartDefinition(
            id: UUID().uuidString,
            number: finalNumber,
            title: title,
            durationMinutes: durationMinutes,
            setting: setting,
            rawMarkdown: "",
            learningPoints: learningPoints,
            observationItems: observationItems,
            positiveItems: positiveItems
        )

        sessions[sessionIndex].parts.append(newPart)

        // Select the new part
        let newPartIndex = sessions[sessionIndex].parts.count - 1
        currentPartIndex = newPartIndex
        partElapsedTime = 0
        sessionState.partStates[newPart.id] = PartState()

        saveCurrentSession()
    }

    func updatePart(
        id: String,
        number: Int,
        title: String,
        durationMinutes: Int?,
        setting: String?,
        learningPointsText: String,
        observationItemsText: String,
        positiveItemsText: String
    ) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
              let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == id }) else { return }

        let part = sessions[sessionIndex].parts[partIndex]

        let newLearningPoints = parseLinesToItems(learningPointsText) { text in
            LearningPoint(id: UUID().uuidString, text: text)
        }
        let newObservationItemsTexts = parseLinesToItems(observationItemsText) { $0 }
        let newPositiveItemsTexts = parseLinesToItems(positiveItemsText) { $0 }

        let obsChanged = newObservationItemsTexts != part.observationItems.map { $0.text }
        let posChanged = newPositiveItemsTexts != part.positiveItems.map { $0.text }

        var finalObservationItems = part.observationItems
        var finalPositiveItems = part.positiveItems
        var newAnalysisState = part.analysisState

        if obsChanged {
            finalObservationItems = newObservationItemsTexts.map { ObservationItem(id: UUID().uuidString, text: $0) }
            newAnalysisState.observationItemStates = Dictionary(
                uniqueKeysWithValues: finalObservationItems.map { ($0.id, AnalysisItemState.hidden(at: clock.now)) }
            )
        }

        if posChanged {
            finalPositiveItems = newPositiveItemsTexts.map { PositiveItem(id: UUID().uuidString, text: $0) }
            newAnalysisState.positiveItemStates = Dictionary(
                uniqueKeysWithValues: finalPositiveItems.map { ($0.id, AnalysisItemState.hidden(at: clock.now)) }
            )
        }

        let updatedPart = PartDefinition(
            id: part.id, // Keep ID
            number: number,
            title: title,
            durationMinutes: durationMinutes,
            setting: setting,
            rawMarkdown: part.rawMarkdown, // Keep
            learningPoints: newLearningPoints,
            observationItems: finalObservationItems,
            positiveItems: finalPositiveItems,
            aiMemo: part.aiMemo, // Keep
            aiMemoBlockId: part.aiMemoBlockId, // Keep
            lastSyncedHash: part.lastSyncedHash, // Keep
            lastSyncedTime: part.lastSyncedTime, // Keep
            aiMemoGenerationError: part.aiMemoGenerationError, // Keep
            analysisState: newAnalysisState
        )

        sessions[sessionIndex].parts[partIndex] = updatedPart
        saveCurrentSession()
    }

    private func parseLinesToItems<T>(
        _ text: String,
        creator: (String) -> T
    ) -> [T] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(creator)
    }

    private func activateSession(_ session: BriefingSession, notionPageId: String?) {
        stopPlayback()
        sessions.append(session)
        self.notionPageId = notionPageId
        self.selectedSessionId = session.id
        userDefaults.set(selectedSessionId, forKey: Self.lastSelectedSessionKey)
        self.currentPartIndex = 0
        self.sessionState = SessionState()
        self.partElapsedTime = 0
        self.transcriptionError = nil
        self.activeRecordingContext = nil
        saveCurrentSession()
    }

    private func setupSubscriptions() {
        micService.statusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.micStatus = status
                if status == .recording {
                    self.debugLog("micService.status -> .recording")
                    self.startTranscription(audioStream: self.micService.createAudioBufferStream(runID: self.currentRunID))
                    self.startTimer()
                } else {
                    if status == .idle {
                        self.debugLog("micService.status -> .idle")
                    } else {
                        self.debugLog("micService.status -> \(status)")
                    }
                    if !self.isFinalizing {
                        Task {
                            await self.stopTranscription()
                        }
                    }
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)

        micService.audioLevelPublisher
            .receive(on: RunLoop.main)
            .assign(to: \.audioLevel, on: self)
            .store(in: &cancellables)

        micService.audioAmplitudePublisher
            .receive(on: RunLoop.main)
            .assign(to: \.audioAmplitude, on: self)
            .store(in: &cancellables)
    }

    var isCurrentPartOvertime: Bool {
        guard let part = currentPart, let durationMinutes = part.durationMinutes else {
            return false
        }
        return partElapsedTime >= Double(durationMinutes * 60)
    }

    var selectedSession: BriefingSession? {
        sessions.first(where: { $0.id == selectedSessionId })
    }

    var sortedSessions: [BriefingSession] {
        switch sortOrder {
        case .nameAsc:     return sessions.sorted { $0.name < $1.name }
        case .nameDesc:    return sessions.sorted { $0.name > $1.name }
        case .updatedAsc:  return sessions.sorted { $0.updatedAt < $1.updatedAt }
        case .updatedDesc: return sessions.sorted { $0.updatedAt > $1.updatedAt }
        case .createdAsc:  return sessions.sorted { $0.createdAt < $1.createdAt }
        case .createdDesc: return sessions.sorted { $0.createdAt > $1.createdAt }
        }
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
        let partId = part.id

        do {
            // 1. LLM Analysis
            let fullTranscript = (sessionState.partStates[partId]?.transcript ?? [])
                .filter { $0.isFinal }
                .map { $0.text }
                .joined(separator: "\n")

            let result = try await llmService.analyzeTranscript(
                fullTranscript: fullTranscript,
                newChunk: chunk.text,
                partInfo: part,
                localeIdentifier: selectedTranscriptionLocale
            )

            // 2. Merge Results into analysisState
            // Re-fetch latest part to avoid overwriting changes from finishPart()
            guard let currentSessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
                  partIndex < sessions[currentSessionIndex].parts.count else { return }

            var latestPart = sessions[currentSessionIndex].parts[partIndex]
            let now = clock.now

            latestPart.analysisState.observationItemStates = mergeMatches(
                existingStates: latestPart.analysisState.observationItemStates,
                matches: result.observationMatches,
                now: now
            )
            latestPart.analysisState.positiveItemStates = mergeMatches(
                existingStates: latestPart.analysisState.positiveItemStates,
                matches: result.positiveMatches,
                now: now
            )

            // Update local state immediately for UI responsiveness
            self.updateLocalPart(latestPart, sessionId: sessionId, partIndex: partIndex)

            // Record LLM Result
            let llmResult = LLMResult(
                observationMatches: result.observationMatches,
                positiveMatches: result.positiveMatches,
                sourceChunkId: chunk.id,
                sourceChunkText: chunk.text,
                sourceChunkStartTime: chunk.startTime,
                sourceChunkEndTime: chunk.endTime
            )
            sessionState.partStates[partId]?.llmResults.append(llmResult)

            saveCurrentSession()
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
        debugLog("selectSession", extra: "target: \(id)")
        let oldPartId = currentPart?.id
        let oldSessionId = selectedSessionId

        // Capture recording state synchronously before state change
        let wasRecording = micStatus == .recording
        let wasStarting = micStatus == .starting

        // Immediate synchronous state update
        selectedSessionId = id
        userDefaults.set(selectedSessionId, forKey: Self.lastSelectedSessionKey)
        currentPartIndex = 0
        transcriptionError = nil
        partElapsedTime = 0
        activeRecordingContext = nil // Invalidate immediately

        Task { @MainActor in
            stopPlayback()

            if wasRecording || wasStarting {
                if wasStarting {
                    micService.cancelPendingOperationsAndStop()
                } else {
                    micService.stopRecording()
                }
                await stopTranscription(sessionId: oldSessionId, partId: oldPartId)
            } else {
                // Not recording, but should still flush
                chunker?.flush()
            }

            await loadSavedSession()
        }
    }

    private var notionPageId: String?

    @MainActor
    private func loadSavedSession() async {
        guard !selectedSessionId.isEmpty else {
            self.sessionState = SessionState()
            self.partElapsedTime = 0
            return
        }

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
                        audioFileNames: partRun.audioFileNames
                    )
                }
                self.sessionState = newState
            } else {
                // If no saved session exists, clear runtime state for this selection.
                self.sessionState = SessionState()
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
        guard var session = selectedSession else { return }

        session.updatedAt = clock.now
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].updatedAt = session.updatedAt
        }

        var partRuns: [String: PartRun] = [:]
        for (partId, partState) in sessionState.partStates {
            var partRun = PartRun(partId: partId)
            partRun.transcript = partState.transcript
            partRun.elapsedTime = partState.elapsedTime
            partRun.isFinished = partState.isFinished
            partRun.llmResults = partState.llmResults
            partRun.finalSummary = partState.finalSummary
            partRun.audioFileNames = partState.audioFileNames

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
    private struct PendingSync: Equatable {
        let blockId: String
        let content: String
        let sessionId: String
        let partId: String
    }
    private var pendingAIMemoUpdate: PendingSync?

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
        let sorted = sortedSessions
        guard let currentIndex = sorted.firstIndex(where: { $0.id == selectedSessionId }) else { return }

        Task { @MainActor in
            let deletedSessionId = selectedSessionId

            activeSaveTask?.cancel()
            activeSaveTask = nil
            pendingSave = nil

            do {
                try await store.deleteSession(sessionId: deletedSessionId)
            } catch {
                print("Failed to delete session: \(error)")
                return
            }

            sessions.removeAll { $0.id == deletedSessionId }

            let remainingSorted = sortedSessions
            if remainingSorted.isEmpty {
                selectedSessionId = ""
                userDefaults.set(selectedSessionId, forKey: Self.lastSelectedSessionKey)
                currentPartIndex = 0
                sessionState = SessionState()
                partElapsedTime = 0
                transcriptionError = nil
                return
            }

            let nextIndex = min(currentIndex, remainingSorted.count - 1)
            selectedSessionId = remainingSorted[nextIndex].id
            userDefaults.set(selectedSessionId, forKey: Self.lastSelectedSessionKey)
            currentPartIndex = 0
            transcriptionError = nil
            partElapsedTime = 0
            await loadSavedSession()
        }
    }

    func deleteCurrentPart() {
        guard let partId = currentPart?.id else { return }

        // Capture recording/starting state
        let wasRecording = micStatus == .recording
        let wasStarting = micStatus == .starting

        let targetPartId = partId
        let targetSessionId = selectedSessionId

        Task { @MainActor in
            stopPlayback()

            if wasRecording || wasStarting {
                if wasStarting {
                    micService.cancelPendingOperationsAndStop()
                } else {
                    micService.stopRecording()
                }
                await stopTranscription(sessionId: targetSessionId, partId: targetPartId)
            }

            // Cleanup storage
            do {
                try await store.deletePart(sessionId: targetSessionId, partId: targetPartId)
            } catch {
                print("Failed to delete part folder: \(error)")
            }

            // Cleanup runtime state
            sessionState.partStates.removeValue(forKey: targetPartId)
            notionSyncStatuses.removeValue(forKey: targetPartId)
            chunkQueue.removeAll { $0.sessionId == targetSessionId && $0.chunk.partId == targetPartId }
            if pendingAIMemoUpdate?.partId == targetPartId {
                pendingAIMemoUpdate = nil
            }
            if activeRecordingContext?.partId == targetPartId {
                activeRecordingContext = nil
            }
            transcriptionError = nil

            // Re-resolve session and part index after awaits
            guard let sessionIndex = sessions.firstIndex(where: { $0.id == targetSessionId }),
                  let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == targetPartId }) else {
                return
            }

            // Remove from session
            sessions[sessionIndex].parts.remove(at: partIndex)

            // Only update selection/timer if the session is still selected
            if selectedSessionId == targetSessionId {
                if sessions[sessionIndex].parts.isEmpty {
                    currentPartIndex = 0
                    partElapsedTime = 0
                } else {
                    let nextIndex = min(partIndex, sessions[sessionIndex].parts.count - 1)
                    currentPartIndex = nextIndex
                    let newPartId = sessions[sessionIndex].parts[nextIndex].id
                    partElapsedTime = sessionState.partStates[newPartId]?.elapsedTime ?? 0
                }
            }

            saveCurrentSession()
        }
    }

    func deleteCurrentPartData(onlyAudio: Bool = false, onlyTranscript: Bool = false, onlyLLM: Bool = false) {
        guard let partId = currentPart?.id else { return }

        // Capture recording state synchronously
        let needsStop = micStatus == .recording || micStatus == .starting

        // Immediate synchronous state update for timer
        partElapsedTime = 0
        if sessionState.partStates[partId] != nil {
            sessionState.partStates[partId]?.elapsedTime = 0
        }

        Task { @MainActor in
            stopPlayback()

            // Stop recording/transcription if active for THIS part
            if needsStop {
                await stopTranscription()
                micService.stopRecording()
            }

            do {
                if !onlyAudio && !onlyTranscript && !onlyLLM {
                    // Delete all for this part
                    try await store.deleteAudio(sessionId: selectedSessionId, partId: partId)
                    try await store.deleteTranscript(sessionId: selectedSessionId, partId: partId)
                    try await store.deleteLLMResults(sessionId: selectedSessionId, partId: partId)

                    // Reset local state for this part (elapsedTime was already reset above, but PartState() also has 0)
                    sessionState.partStates[partId] = PartState()
                    if let sessionIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }),
                       let partIndex = sessions[sessionIndex].parts.firstIndex(where: { $0.id == partId }) {
                        let part = sessions[sessionIndex].parts[partIndex]
                        sessions[sessionIndex].parts[partIndex].analysisState = PartAnalysisState.initial(
                            observationItems: part.observationItems,
                            positiveItems: part.positiveItems
                        )
                        sessions[sessionIndex].parts[partIndex].aiMemo = ""
                        sessions[sessionIndex].parts[partIndex].lastSyncedHash = nil
                        sessions[sessionIndex].parts[partIndex].lastSyncedTime = nil
                    }
                } else {
                    if onlyAudio {
                        try await store.deleteAudio(sessionId: selectedSessionId, partId: partId)
                        sessionState.partStates[partId]?.audioFileNames = []
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
        stopPlayback()
        #if DEBUG
        let newRunID = String(UUID().uuidString.prefix(8))
        self.currentRunID = newRunID
        #endif
        guard let partId = currentPart?.id else { return }
        let isFinished = sessionState.partStates[partId]?.isFinished ?? false
        guard !isFinished else { return }

        let recordingId = UUID().uuidString
        let audioURL = store.getAudioURL(sessionId: selectedSessionId, partId: partId, recordingId: recordingId)

        // Update local state to track this audio file
        var partState = sessionState.partStates[partId] ?? PartState()
        partState.audioFileNames.append(audioURL.lastPathComponent)
        sessionState.partStates[partId] = partState

        micService.startRecording(audioFileURL: audioURL, runID: currentRunID)
    }

    func pauseRecording() {
        Task {
            await stopTranscription(caller: "pauseRecording") // This ensures segments are finalized
            micService.stopRecording()
            saveCurrentSession()
        }
    }

    @MainActor
    func finishPart() async {
        guard !isFinalizing, !isGeneratingAIMemo else { return }
        guard let part = currentPart else { return }

        let targetSessionId = selectedSessionId
        let targetPartIndex = currentPartIndex

        isFinalizing = true
        defer { isFinalizing = false }
        stopPlayback()

        // 1. Stop recording and flush
        micService.stopRecording()
        await stopTranscription(sessionId: targetSessionId, partId: part.id, caller: "finishPart")

        // 2. Wait for queue to settle
        while !chunkQueue.isEmpty || isProcessing {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        // 3. Finalization Processing
        // Re-fetch part after wait to get latest analysis results
        guard let session = sessions.first(where: { $0.id == targetSessionId }),
              targetPartIndex < session.parts.count else {
            return
        }
        let latestPart = session.parts[targetPartIndex]

        await generateAndSyncAIMemo(
            part: latestPart,
            sessionId: targetSessionId,
            partIndex: targetPartIndex,
            isManual: false
        )

        // Re-fetch part and session state once more after AI memo generation to ensure we have everything
        guard let finalSession = sessions.first(where: { $0.id == targetSessionId }),
              targetPartIndex < finalSession.parts.count else {
            return
        }
        let finalPartId = finalSession.parts[targetPartIndex].id

        // 6. Mark as finished
        var partState = sessionState.partStates[finalPartId] ?? PartState()
        partState.isFinished = true
        sessionState.partStates[finalPartId] = partState

        saveCurrentSession()
    }

    func regenerateAIMemo() {
        guard let part = currentPart, !isGeneratingAIMemo, !isFinalizing else { return }

        let targetSessionId = selectedSessionId
        let targetPartIndex = currentPartIndex
        let transcript = getCurrentTranscript(for: part.id)

        Task {
            await generateAndSyncAIMemo(
                part: part,
                sessionId: targetSessionId,
                partIndex: targetPartIndex,
                transcriptOverride: transcript,
                isManual: true
            )
        }
    }

    private func getCurrentTranscript(for partId: String) -> String {
        return (sessionState.partStates[partId]?.transcript ?? [])
            .map { $0.text }
            .joined(separator: "\n")
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
        let targetPartId = session.parts[index].id
        let oldSessionId = selectedSessionId

        // Capture recording state synchronously
        let wasRecording = micStatus == .recording
        let wasStarting = micStatus == .starting

        // Immediate synchronous state update
        currentPartIndex = index
        partElapsedTime = sessionState.partStates[targetPartId]?.elapsedTime ?? 0
        activeRecordingContext = nil // Invalidate immediately

        Task { @MainActor in
            stopPlayback()

            if wasRecording || wasStarting {
                if wasStarting {
                    micService.cancelPendingOperationsAndStop()
                } else {
                    micService.stopRecording()
                }
                await stopTranscription(sessionId: oldSessionId, partId: oldPartId, caller: "selectPart")
            } else {
                // Not recording, but should still flush
                chunker?.flush()
            }
        }
    }

    // MARK: - Playback

    func startPlayback() {
        guard let partId = currentPart?.id,
              let fileNames = sessionState.partStates[partId]?.audioFileNames,
              !fileNames.isEmpty else { return }

        stopPlayback()

        let partDir = store.getPartDirectory(sessionId: selectedSessionId, partId: partId)
        playbackQueue = fileNames.map { fileName in
            partDir.appendingPathComponent(fileName)
        }

        // Filter out non-existent files just in case
        playbackQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !playbackQueue.isEmpty else { return }

        currentPlaybackIndex = 0
        isPlaying = true
        playNextInQueue()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackQueue = []
        currentPlaybackIndex = 0
    }

    private func playNextInQueue() {
        guard currentPlaybackIndex < playbackQueue.count else {
            stopPlayback()
            return
        }

        let url = playbackQueue[currentPlaybackIndex]
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            print("Failed to play audio: \(error)")
            currentPlaybackIndex += 1
            playNextInQueue()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.currentPlaybackIndex += 1
            self.playNextInQueue()
        }
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
        debugLog("startTranscription")
        transcriptionError = nil
        transcriptionTask?.cancel()

        let context = RecordingContext(
            sessionId: selectedSessionId,
            partId: currentPart?.id ?? ""
        )
        activeRecordingContext = context
        let locale = selectedTranscriptionLocale

        transcriptionTask = Task {
            do {
                await transcriptionService.stopTranscription()
                let results = try await transcriptionService.startTranscription(
                    audioStream: audioStream,
                    localeIdentifier: locale,
                    runID: self.currentRunID
                )

                for await segment in results {
                    // Only process segments if they match the context when they were received
                    guard let activeContext = self.activeRecordingContext,
                          activeContext == context else {
                        continue
                    }

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
                if error is CancellationError { return }
                guard let activeContext = self.activeRecordingContext,
                      activeContext == context else { return }

                self.transcriptionError = error.localizedDescription
            }
        }
    }

    @MainActor
    func stopTranscription(sessionId: String? = nil, partId: String? = nil, caller: String? = nil) async {
        let targetPartId = partId ?? activeRecordingContext?.partId ?? currentPart?.id
        let targetSessionId = sessionId ?? activeRecordingContext?.sessionId ?? selectedSessionId

        await transcriptionService.stopTranscription()

        activeRecordingContext = nil

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

        if transcriptionTask != nil {
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
    }

    // MARK: - Notion Sync logic

    func triggerNotionSync(blockId: String, content: String, sessionId: String, partId: String) {
        pendingAIMemoUpdate = PendingSync(blockId: blockId, content: content, sessionId: sessionId, partId: partId)
        guard notionSyncTask == nil else { return }

        notionSyncTask = Task { @MainActor in
            while let sync = pendingAIMemoUpdate {
                // Throttle: if same content as last synced, skip
                if let session = sessions.first(where: { $0.id == sync.sessionId }),
                   let part = session.parts.first(where: { $0.id == sync.partId }),
                   part.lastSyncedHash == CryptoUtils.calculateHash(content: sync.content) {
                    pendingAIMemoUpdate = nil
                    break
                }

                pendingAIMemoUpdate = nil
                await performNotionSync(blockId: sync.blockId, content: sync.content, sessionId: sync.sessionId, partId: sync.partId)
            }
            notionSyncTask = nil
        }
    }

    private func syncNotionImmediately(blockId: String, content: String, sessionId: String, partId: String) async {
        pendingAIMemoUpdate = nil
        notionSyncTask?.cancel()
        notionSyncTask = nil
        await performNotionSync(blockId: blockId, content: content, sessionId: sessionId, partId: partId)
    }

    @MainActor
    private func performNotionSync(blockId: String, content: String, sessionId: String, partId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }),
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
            #if DEBUG
            print("result: \(result)")
            #endif
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
        let content = part.aiMemo
        if content.isEmpty && part.aiMemoGenerationError != nil {
            // Generation failed previously, retry generation
            let targetSessionId = selectedSessionId
            let targetPartIndex = currentPartIndex
            Task {
                await generateAndSyncAIMemo(
                    part: part,
                    sessionId: targetSessionId,
                    partIndex: targetPartIndex,
                    isManual: false
                )
            }
            return
        }

        // If we have content, retry sync
        guard !content.isEmpty else { return }

        let positives = getSummarizedItems(
            items: part.positiveItems,
            states: part.analysisState.positiveItemStates
        )
        let observationsForAll = part.observationItems.map { item in
            let state = part.analysisState.observationItemStates[item.id] ?? .hidden()
            return SummarizedItem(id: item.id, text: item.text, evidence: state.shortEvidence)
        }

        let fullContent = buildNotionContent(positives: positives, observations: observationsForAll, aiMemo: content)

        triggerNotionSync(blockId: blockId, content: fullContent, sessionId: selectedSessionId, partId: part.id)
    }

    @MainActor
    func handleTranscriptSegment(_ segment: TranscriptSegment) async {
        let partId = segment.partId
        guard !partId.isEmpty else {
            return
        }

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

            // Only overwrite if incoming is final OR existing is provisional
            if segment.isFinal || !existing.isFinal {
                let wasFinal = existing.isFinal

                // Only save/process if it's becoming final OR text changed (for provisional)
                // BUT following ID-match pattern: only set shouldSave if it just became final.
                // Wait, ID-match only sets shouldSave if (segment.isFinal && !wasFinal).
                // Let's align exactly.

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

    @MainActor
    private func generateAndSyncAIMemo(
        part: PartDefinition,
        sessionId: String,
        partIndex: Int,
        transcriptOverride: String? = nil,
        isManual: Bool = false
    ) async {
        guard !isGeneratingAIMemo else { return }
        isGeneratingAIMemo = true
        defer { isGeneratingAIMemo = false }

        let fullTranscript = transcriptOverride ?? getCurrentTranscript(for: part.id)

        let positives = getSummarizedItems(
            items: part.positiveItems,
            states: part.analysisState.positiveItemStates
        )
        let observations = getSummarizedItems(
            items: part.observationItems,
            states: part.analysisState.observationItemStates
        )

        // For Notion output, we want all displayed items.
        // Observations: all items are displayed in the UI.
        // Positives: only non-hidden items are displayed.
        let observationsForAll = part.observationItems.map { item in
            let state = part.analysisState.observationItemStates[item.id] ?? .hidden()
            return SummarizedItem(id: item.id, text: item.text, evidence: state.shortEvidence)
        }

        var finalMemo: String? = nil
        var generationError: String? = nil

        if !positives.isEmpty || !observations.isEmpty || !fullTranscript.isEmpty {
            do {
                finalMemo = try await llmService.generateOneLiner(
                    partInfo: part,
                    fullTranscript: fullTranscript,
                    positives: positives,
                    observations: observations,
                    localeIdentifier: selectedTranscriptionLocale
                )
            } catch {
                print("Failed to generate comment material: \(error)")
                generationError = error.localizedDescription
            }
        }

        // Update local state
        // Re-fetch latest part definition to preserve concurrent analysis updates
        guard var updatedPart = sessions.first(where: { $0.id == sessionId })?.parts.first(where: { $0.id == part.id }) else { return }

        updatedPart.aiMemo = finalMemo ?? ""
        updatedPart.aiMemoGenerationError = generationError
        updateLocalPart(updatedPart, sessionId: sessionId, partIndex: partIndex)

        if let finalMemo = finalMemo {
            if !isManual {
                // Record Final Summary
                let finalSummary = FinalSummary(
                    text: finalMemo,
                    adoptedItemIds: positives.map { $0.id } + observations.map { $0.id },
                    sourceLLMResultIds: sessionState.partStates[part.id]?.llmResults.map { $0.id } ?? []
                )
                sessionState.partStates[part.id]?.finalSummary = finalSummary
            }

            // Notion Update (Wait for final sync)
            if let blockId = updatedPart.aiMemoBlockId {
                let fullContent = buildNotionContent(positives: positives, observations: observationsForAll, aiMemo: finalMemo)
                await syncNotionImmediately(blockId: blockId, content: fullContent, sessionId: sessionId, partId: part.id)
            }
        }

        if sessionId == selectedSessionId {
            saveCurrentSession()
        }
    }

    private func buildNotionContent(
        positives: [SummarizedItem],
        observations: [SummarizedItem],
        aiMemo: String
    ) -> String {
        Self.assembleNotionContent(
            positives: positives,
            observations: observations,
            aiMemo: aiMemo
        )
    }

    nonisolated internal static func assembleNotionContent(
        positives: [SummarizedItem],
        observations: [SummarizedItem],
        aiMemo: String
    ) -> String {
        var sections: [String] = []

        // 1. 良かった点候補
        var positiveSection = NSLocalizedString("notion.section.positives", comment: "")
        for item in positives {
            positiveSection += "\n- \(item.text)\(item.evidence)"
        }
        sections.append(positiveSection)

        // 2. 観察メモ
        var observationSection = NSLocalizedString("notion.section.observations", comment: "")
        for item in observations {
            observationSection += "\n- \(item.text)\(item.evidence)"
        }
        sections.append(observationSection)

        // 3. コメント素材
        if !aiMemo.isEmpty {
            sections.append("\(NSLocalizedString("notion.section.aiMemo", comment: ""))\n\(aiMemo)")
        }

        return sections.joined(separator: "\n\n")
    }

    func getSummarizedItems<T: SummaryItemProtocol>(
        items: [T],
        states: [String: AnalysisItemState]
    ) -> [SummarizedItem] {
        var sortableItems: [SortableItem] = []

        for item in items {
            if let state = states[item.id], state.status != .hidden {
                sortableItems.append(SortableItem(id: item.id, text: item.text, state: state))
            }
        }

        return sortableItems
            .sorted { (a, b) -> Bool in
                if a.state.status != b.state.status {
                    return a.state.status > b.state.status
                }
                return a.state.confidence > b.state.confidence
            }
            .map { SummarizedItem(id: $0.id, text: $0.text, evidence: $0.state.shortEvidence) }
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
    let id: String
    let text: String
    let state: AnalysisItemState
}
