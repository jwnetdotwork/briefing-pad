import XCTest
import Combine
import AVFoundation
@testable import BriefingPad

final class SessionControlTests: XCTestCase {

    private func makeTempStore() -> (FileSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (FileSessionStore(rootURL: tempDir), tempDir)
    }

    @MainActor
    private func expectationForPublishedValue<T: Equatable>(
        _ publisher: Published<T>.Publisher,
        equals expected: T,
        description: String
    ) -> (XCTestExpectation, AnyCancellable) {
        let expectation = XCTestExpectation(description: description)
        let cancellable = publisher.sink { value in
            if value == expected {
                expectation.fulfill()
            }
        }
        return (expectation, cancellable)
    }

    @MainActor
    func testSessionControlFlow() async {
        let mockMic = MockMicrophoneService()
        // Use MockSessionStore to avoid file I/O for logic tests
        let viewModel = SessionViewModel(
            llmService: MockLLMService(delayNanoseconds: 0),
            micService: mockMic,
            store: MockSessionStore()
        )

        let part1Id = "part1"
        let part2Id = "part2"
        let session = BriefingSession(id: "s1", name: "Session 1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "Part 1", durationMinutes: 5, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [ObservationItem(id: "obs1", text: "Obs 1")], positiveItems: []),
            PartDefinition(id: part2Id, number: 2, title: "Part 2", durationMinutes: 5, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])

        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"
        viewModel.currentPartIndex = 0

        // 1. Start Recording
        XCTAssertEqual(viewModel.micStatus, .idle)
        viewModel.startRecording()
        XCTAssertEqual(mockMic.startRecordingCalled, true)

        // Verify mic status updates correctly via subscription
        let (recordingExpectation, recordingCancellable) = expectationForPublishedValue(
            viewModel.$micStatus,
            equals: .recording,
            description: "ViewModel micStatus updates to recording"
        )
        mockMic.status = .recording
        await fulfillment(of: [recordingExpectation], timeout: 1.0)
        recordingCancellable.cancel()

        XCTAssertEqual(viewModel.micStatus, .recording)

        // 2. Pause Recording
        let (pauseExpectation, pauseCancellable) = expectationForPublishedValue(
            viewModel.$micStatus,
            equals: .idle,
            description: "micStatus becomes idle after pause"
        )
        viewModel.pauseRecording()
        await fulfillment(of: [pauseExpectation], timeout: 1.0)
        pauseCancellable.cancel()
        XCTAssertEqual(mockMic.stopRecordingCalled, true)

        // 3. Finish Part
        await viewModel.finishPart()
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.isFinished, true)

        // 4. Move to Next Part
        let (nextPartExpectation, nextPartCancellable) = expectationForPublishedValue(
            viewModel.$currentPartIndex,
            equals: 1,
            description: "currentPartIndex updates to next part"
        )
        viewModel.moveToNextPart()
        await fulfillment(of: [nextPartExpectation], timeout: 1.0)
        nextPartCancellable.cancel()
        XCTAssertEqual(viewModel.currentPartIndex, 1)
        XCTAssertEqual(viewModel.currentPart?.id, part2Id)

        // 5. Back to Previous Part
        let (previousPartExpectation, previousPartCancellable) = expectationForPublishedValue(
            viewModel.$currentPartIndex,
            equals: 0,
            description: "currentPartIndex updates to previous part"
        )
        viewModel.moveToPreviousPart()
        await fulfillment(of: [previousPartExpectation], timeout: 1.0)
        previousPartCancellable.cancel()
        XCTAssertEqual(viewModel.currentPartIndex, 0)
        XCTAssertEqual(viewModel.currentPart?.id, part1Id)
    }

    @MainActor
    func testPartSwitchResetsTimer() async throws {
        let viewModel = SessionViewModel(store: MockSessionStore())
        let part1Id = "p1"
        let part2Id = "p2"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: []),
            PartDefinition(id: part2Id, number: 2, title: "P2", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Set some elapsed time for Part 1 in the session state
        viewModel.currentPartIndex = 0
        var p1State = PartState()
        p1State.elapsedTime = 100
        viewModel.sessionState.partStates[part1Id] = p1State
        viewModel.partElapsedTime = 100

        // 2. Switch to Part 2
        viewModel.selectPart(index: 1)
        // Verify immediate state update
        XCTAssertEqual(viewModel.currentPartIndex, 1)
        XCTAssertEqual(viewModel.partElapsedTime, 0, "Timer should be reset to 0 for a new part with no history")

        // 3. Set elapsed time for Part 2
        var p2State = PartState()
        p2State.elapsedTime = 50
        viewModel.sessionState.partStates[part2Id] = p2State
        viewModel.partElapsedTime = 50

        // 4. Switch back to Part 1
        viewModel.selectPart(index: 0)
        // Verify immediate state update
        XCTAssertEqual(viewModel.currentPartIndex, 0)
        XCTAssertEqual(viewModel.partElapsedTime, 100, "Timer should restore Part 1's value")
    }

    @MainActor
    func testRecordingContextIsolation() async {
        let viewModel = SessionViewModel(
            transcriptionService: MockSpeechTranscriptionService(),
            store: MockSessionStore()
        )
        let part1Id = "p1"
        let part2Id = "p2"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: []),
            PartDefinition(id: part2Id, number: 2, title: "P2", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Start transcription for Part 1
        viewModel.currentPartIndex = 0
        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in continuation.finish() }
        viewModel.startTranscription(audioStream: audioStream)
        await Task.yield()

        // 2. Switch to Part 2 (This should reset context and stop transcription)
        viewModel.selectPart(index: 1)
        // Verify immediate state update
        XCTAssertEqual(viewModel.currentPartIndex, 1)

        // 3. Assertions
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.transcript.count ?? 0, 0, "Late segment from old context should be ignored")
        XCTAssertEqual(viewModel.sessionState.partStates[part2Id]?.transcript.count ?? 0, 0, "Late segment should not go into new part")
    }

    @MainActor
    func testLoadsSessionsOnlyFromStore() async throws {
        let (store, tempDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionId = "saved-session"
        let template = BriefingSession(
            id: sessionId,
            name: "Saved Session",
            parts: [
                PartDefinition(id: "part-1", number: 1, title: "P1", durationMinutes: 5, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
            ]
        )
        let savedSession = SavedSession(sessionId: sessionId, templateSnapshot: template, updatedAt: Date(), partRuns: [:])
        try await store.saveSession(savedSession)

        // Here we MUST use FileSessionStore because we are testing loading from it
        let viewModel = SessionViewModel(store: store)
        let (loadedExpectation, loadedCancellable) = expectationForPublishedValue(
            viewModel.$selectedSessionId,
            equals: sessionId,
            description: "saved session loads from store"
        )
        await fulfillment(of: [loadedExpectation], timeout: 1.0)
        loadedCancellable.cancel()

        XCTAssertEqual(viewModel.sessions.map(\.id), [sessionId])
        XCTAssertEqual(viewModel.selectedSessionId, sessionId)
    }

    @MainActor
    func testDeleteCurrentSessionRemovesFromListAndSelectsNext() async throws {
        let viewModel = SessionViewModel(store: MockSessionStore())
        let session1 = BriefingSession(id: "s1", name: "Session 1", parts: [])
        let session2 = BriefingSession(id: "s2", name: "Session 2", parts: [])
        let session3 = BriefingSession(id: "s3", name: "Session 3", parts: [])
        viewModel.sessions = [session1, session2, session3]
        viewModel.selectedSessionId = "s2"

        viewModel.deleteCurrentSession()

        try await waitUntil(message: "selected session moved") {
            viewModel.selectedSessionId == "s3"
        }

        XCTAssertEqual(viewModel.sessions.map(\.id), ["s1", "s3"])
        XCTAssertEqual(viewModel.selectedSessionId, "s3")
    }

    @MainActor
    func testDeleteLastSessionLeavesNoSelection() async throws {
        let viewModel = SessionViewModel(store: MockSessionStore())
        let session = BriefingSession(id: "s1", name: "Session 1", parts: [])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        viewModel.deleteCurrentSession()

        try await waitUntil(message: "selection cleared") {
            viewModel.selectedSessionId == ""
        }

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertEqual(viewModel.selectedSessionId, "")
        XCTAssertNil(viewModel.selectedSession)
    }

    @MainActor
    func testDeletePartDataResetsTimerInAllModes() async throws {
        let viewModel = SessionViewModel(store: MockSessionStore())
        let part1Id = "p1"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"
        viewModel.currentPartIndex = 0

        // Helper to set and verify reset
        let setupData: ( (SessionViewModel) -> Void ) = { vm in
            vm.partElapsedTime = 100
            vm.sessionState.partStates[part1Id] = PartState()
            vm.sessionState.partStates[part1Id]?.elapsedTime = 100
        }

        // 1. Full deletion
        setupData(viewModel)
        viewModel.deleteCurrentPartData()
        // Verify immediate state update
        XCTAssertEqual(viewModel.partElapsedTime, 0)
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.elapsedTime, 0)

        // 2. Only Audio
        setupData(viewModel)
        viewModel.deleteCurrentPartData(onlyAudio: true)
        // Verify immediate state update
        XCTAssertEqual(viewModel.partElapsedTime, 0)
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.elapsedTime, 0)

        // 3. Only Transcript
        setupData(viewModel)
        viewModel.deleteCurrentPartData(onlyTranscript: true)
        // Verify immediate state update
        XCTAssertEqual(viewModel.partElapsedTime, 0)
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.elapsedTime, 0)

        // 4. Only LLM
        setupData(viewModel)
        viewModel.deleteCurrentPartData(onlyLLM: true)
        // Verify immediate state update
        XCTAssertEqual(viewModel.partElapsedTime, 0)
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.elapsedTime, 0)
    }

    @MainActor
    func testOvertimeDetection() {
        let viewModel = SessionViewModel(store: MockSessionStore())
        let part1Id = "p1"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"
        viewModel.currentPartIndex = 0

        // 5 minutes = 300 seconds
        viewModel.partElapsedTime = 299
        XCTAssertFalse(viewModel.isCurrentPartOvertime)

        viewModel.partElapsedTime = 300
        XCTAssertTrue(viewModel.isCurrentPartOvertime, "Overtime should trigger exactly at the limit (>=)")

        viewModel.partElapsedTime = 301
        XCTAssertTrue(viewModel.isCurrentPartOvertime)

        // No duration set
        let part2Id = "p2"
        let session2 = BriefingSession(id: "s2", name: "S2", parts: [
            PartDefinition(id: part2Id, number: 1, title: "P2", durationMinutes: nil, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions.append(session2)
        viewModel.selectedSessionId = "s2"
        viewModel.currentPartIndex = 0
        viewModel.partElapsedTime = 1000
        XCTAssertFalse(viewModel.isCurrentPartOvertime, "Should not be overtime if duration is nil")
    }
}
