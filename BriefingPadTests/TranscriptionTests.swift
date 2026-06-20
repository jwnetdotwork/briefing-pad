import XCTest
@testable import BriefingPad

final class TranscriptionTests: XCTestCase {

    func testTranscriptSegmentInitialization() {
        let id = UUID()
        let now = Date()
        let segment = TranscriptSegment(id: id, text: "Hello", isFinal: true, startTime: 1.0, endTime: 2.0, receivedAt: now)

        XCTAssertEqual(segment.id, id)
        XCTAssertEqual(segment.text, "Hello")
        XCTAssertTrue(segment.isFinal)
        XCTAssertEqual(segment.startTime, 1.0)
        XCTAssertEqual(segment.endTime, 2.0)
        XCTAssertEqual(segment.receivedAt, now)
    }

    func testSessionStateManagement() {
        var state = SessionState()
        let partId = "part-1"
        var partState = PartState()

        let segment = TranscriptSegment(text: "Test", isFinal: true)
        partState.transcript.append(segment)
        state.partStates[partId] = partState

        XCTAssertEqual(state.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(state.partStates[partId]?.transcript.first?.text, "Test")
    }

    @MainActor
    func testProvisionalToFinalUpdate() async {
        let viewModel = SessionViewModel()
        let partId = "test-part"
        let segmentId = UUID()

        // Mock current part
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Add provisional
        let provisional = TranscriptSegment(id: segmentId, text: "認識中...", isFinal: false)
        await viewModel.handleTranscriptSegment(provisional)

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "認識中...")
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.transcript.first?.isFinal ?? true)

        // 2. Update to final
        let final = TranscriptSegment(id: segmentId, text: "確定したテキスト", isFinal: true)
        await viewModel.handleTranscriptSegment(final)

        // Should be replaced, not duplicated
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "確定したテキスト")
        XCTAssertTrue(viewModel.sessionState.partStates[partId]?.transcript.first?.isFinal ?? false)
    }
}
