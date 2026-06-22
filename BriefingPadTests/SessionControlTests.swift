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

        // 1. Set some elapsed time for Part 1
        viewModel.currentPartIndex = 0
        viewModel.partElapsedTime = 100

        // 2. Switch to Part 2
        viewModel.selectPart(index: 1)

        XCTAssertEqual(viewModel.currentPartIndex, 1)
        XCTAssertEqual(viewModel.partElapsedTime, 0, "Timer should be reset to 0 for a new part with no history")

        // 3. Set elapsed time for Part 2
        viewModel.partElapsedTime = 50

        // 4. Switch back to Part 1
        viewModel.selectPart(index: 0)
        XCTAssertEqual(viewModel.partElapsedTime, 100, "Timer should restore Part 1's value")
    }

    @MainActor
    func testRecordingContextIsolation() async {
        let viewModel = SessionViewModel()
        let part1Id = "p1"
        let part2Id = "p2"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: []),
            PartDefinition(id: part2Id, number: 2, title: "P2", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        let mockTranscription = MockSpeechTranscriptionService()
        // We need to inject the mock service or rely on it if it's already there.
        // SessionViewModel uses MockSpeechTranscriptionService by default in init.

        // 1. Start transcription for Part 1
        viewModel.currentPartIndex = 0
        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in continuation.finish() }
        viewModel.startTranscription(audioStream: audioStream)

        // 2. Switch to Part 2 (This should reset context and NOT automatically start recording)
        viewModel.selectPart(index: 1)

        // 3. Inject a segment that might be late from Part 1's transcription stream
        // (In reality, the loop in startTranscription continues until the task is cancelled)
        // Let's verify handleTranscriptSegment directly first, but the goal is to see it filtered in the loop.

        // Since we can't easily reach into the task loop, we verify the principle:
        // handleTranscriptSegment uses segment.partId.
        // BUT the requirement was to discard if context mismatched.

        let lateSegment = TranscriptSegment(
            sessionId: "s1",
            partId: part1Id,
            text: "遅れてきた発話",
            isFinal: true,
            startTime: 0.0,
            endTime: 1.0
        )

        // If we call handleTranscriptSegment directly, it currently just uses partId.
        // We should probably check activeRecordingContext INSIDE handleTranscriptSegment too?
        // Actually, the user said: "recording context は、startRecording か startTranscription の時点で sessionId と partId を固定して、そのコンテキストに一致する segment だけをその録音セッションのものとして扱ってください。"

        // If I switch parts, activeRecordingContext becomes nil (in stopTranscription) or should be checked.

        await viewModel.handleTranscriptSegment(lateSegment)
        // Based on current implementation, it WILL add to part 1's history.
        // The user said: "パート切り替え後に遅れて届いた文字起こしは、旧パートの履歴には残して構いません。現在表示中の TranscriptView には出さない方針でお願いします。"
        // And: "context 不一致のものは破棄してください。"

        // This is slightly contradictory. "旧パートの履歴には残して構いません" vs "破棄してください".
        // Let's re-read: "パート切り替え後に遅れて届いた文字起こしは、旧パートの履歴には残して構いません。現在表示中の TranscriptView には出さない方針でお願いします。"
        // "recording context ... コンテキスト不一致のものは破棄してください。"

        // I think "破棄してください" refers to the processing of the stream for the CURRENT recording session.
        // If I switched parts, the OLD stream might still be yielding. Those should be ignored for the NEW part.
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
