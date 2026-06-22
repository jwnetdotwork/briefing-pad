import XCTest
import Combine
@testable import BriefingPad

final class SessionControlTests: XCTestCase {

    @MainActor
    func testSessionControlFlow() async {
        let obs1 = ObservationItem(id: "obs1", text: "Obs 1")
        let part1 = PartDefinition(
            id: "part1",
            number: 1,
            title: "Part 1",
            durationMinutes: 5,
            setting: nil,
            rawMarkdown: "",
            learningPoints: [],
            observationItems: [obs1],
            positiveItems: []
        )
        let part2 = PartDefinition(
            id: "part2",
            number: 2,
            title: "Part 2",
            durationMinutes: 5,
            setting: nil,
            rawMarkdown: "",
            learningPoints: [],
            observationItems: [],
            positiveItems: []
        )

        let session = BriefingSession(id: "s1", name: "Session 1", parts: [part1, part2])

        let mockMic = MockMicrophoneService()
        let viewModel = SessionViewModel(micService: mockMic)
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Start Recording
        XCTAssertEqual(viewModel.micStatus, .idle)
        viewModel.startRecording()
        XCTAssertEqual(mockMic.startRecordingCalled, true)

        // Verify mic status updates correctly via subscription
        let expectation = XCTestExpectation(description: "ViewModel micStatus updates to recording")
        let cancellable = viewModel.$micStatus
            .dropFirst() // Initial state is idle
            .sink { status in
                if status == .recording {
                    expectation.fulfill()
                }
            }

        mockMic.status = .recording
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(viewModel.micStatus, .recording)

        // 2. Pause Recording
        viewModel.pauseRecording()
        XCTAssertEqual(mockMic.stopRecordingCalled, true)

        // 3. Finish Part
        viewModel.finishPart()
        XCTAssertEqual(viewModel.sessionState.partStates["part1"]?.isFinished, true)

        // 4. Move to Next Part
        viewModel.moveToNextPart()
        XCTAssertEqual(viewModel.currentPartIndex, 1)
        XCTAssertEqual(viewModel.currentPart?.id, "part2")

        // 5. Back to Previous Part
        viewModel.moveToPreviousPart()
        XCTAssertEqual(viewModel.currentPartIndex, 0)
        XCTAssertEqual(viewModel.currentPart?.id, "part1")
    }

    @MainActor
    func testPartSwitchResetsTimer() async {
        let viewModel = SessionViewModel()
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

        XCTAssertEqual(viewModel.currentPartIndex, 1)
        XCTAssertEqual(viewModel.partElapsedTime, 0, "Timer should be reset to 0 for a new part with no history")

        // 3. Set elapsed time for Part 2
        var p2State = PartState()
        p2State.elapsedTime = 50
        viewModel.sessionState.partStates[part2Id] = p2State
        viewModel.partElapsedTime = 50

        // 4. Switch back to Part 1
        viewModel.selectPart(index: 0)
        XCTAssertEqual(viewModel.partElapsedTime, 100, "Timer should restore Part 1's value")
    }

    @MainActor
    func testRecordingContextIsolation() async {
        let mockTranscription = MockSpeechTranscriptionService()
        let viewModel = SessionViewModel(transcriptionService: mockTranscription)
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

        // Give the task a moment to start
        try? await Task.sleep(nanoseconds: 10_000_000)

        // 2. Switch to Part 2 (This should reset context and stop transcription)
        viewModel.selectPart(index: 1)

        // 3. Simulate a late segment arriving from the OLD stream
        // The transcription service loop should be running and checking context.
        mockTranscription.resultsContinuation?.yield(SpeechRecognitionResult(
            text: "遅れてきた発話",
            isFinal: true,
            startTime: 0.0,
            endTime: 1.0
        ))

        // Give it a moment to process (or be filtered)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // 4. Assertions
        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.transcript.count ?? 0, 0, "Late segment from old context should be ignored")
        XCTAssertEqual(viewModel.sessionState.partStates[part2Id]?.transcript.count ?? 0, 0, "Late segment should not go into new part")
    }
}

class MockMicrophoneService: MicrophoneService {
    var startRecordingCalled = false
    var stopRecordingCalled = false

    override func startRecording() {
        startRecordingCalled = true
    }

    override func stopRecording() {
        stopRecordingCalled = true
        status = .idle
    }
}
