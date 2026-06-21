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
