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
}
