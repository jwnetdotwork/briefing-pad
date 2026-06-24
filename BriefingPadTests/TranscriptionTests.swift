import XCTest
@testable import BriefingPad

final class TranscriptionTests: XCTestCase {

    func testTranscriptSegmentInitialization() {
        let id = UUID()
        let now = Date()
        let segment = TranscriptSegment(
            id: id,
            sessionId: "s1",
            partId: "p1",
            text: "Hello",
            isFinal: true,
            startTime: 1.0,
            endTime: 2.0,
            receivedAt: now
        )

        XCTAssertEqual(segment.id, id)
        XCTAssertEqual(segment.sessionId, "s1")
        XCTAssertEqual(segment.partId, "p1")
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

        let segment = TranscriptSegment(
            sessionId: "s1",
            partId: partId,
            text: "Test",
            isFinal: true,
            startTime: 0.0,
            endTime: 1.0
        )
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
        let provisional = TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: partId,
            text: "認識中...",
            isFinal: false,
            startTime: 0.0,
            endTime: 0.0
        )
        await viewModel.handleTranscriptSegment(provisional)

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "認識中...")
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.transcript.first?.isFinal ?? true)

        // 2. Update to final
        let final = TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: partId,
            text: "確定したテキスト",
            isFinal: true,
            startTime: 0.0,
            endTime: 1.0
        )
        await viewModel.handleTranscriptSegment(final)

        // Should be replaced, not duplicated
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "確定したテキスト")
        XCTAssertTrue(viewModel.sessionState.partStates[partId]?.transcript.first?.isFinal ?? false)
    }

    @MainActor
    func testMultipleProvisionalUpdates() async {
        let viewModel = SessionViewModel()
        let partId = "test-part"
        let segmentId = UUID()

        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Provisional 1
        await viewModel.handleTranscriptSegment(TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: partId,
            text: "あいう",
            isFinal: false,
            startTime: 0.0,
            endTime: 0.0
        ))

        // 2. Provisional 2 (same ID)
        await viewModel.handleTranscriptSegment(TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: partId,
            text: "あいうえお",
            isFinal: false,
            startTime: 0.0,
            endTime: 0.5
        ))

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "あいうえお")

        // 3. Final (same ID)
        await viewModel.handleTranscriptSegment(TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: partId,
            text: "あいうえお。",
            isFinal: true,
            startTime: 0.0,
            endTime: 1.0
        ))

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1)
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.first?.text, "あいうえお。")
        XCTAssertTrue(viewModel.sessionState.partStates[partId]?.transcript.first?.isFinal ?? false)
    }

    @MainActor
    func testStopTranscriptionContextSafety() async {
        let viewModel = SessionViewModel()
        let part1Id = "p1"
        let part2Id = "p2"

        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: part1Id, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: []),
            PartDefinition(id: part2Id, number: 2, title: "P2", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"
        viewModel.currentPartIndex = 0 // Part 1

        // startTranscription で activeRecordingContext を Part 1 に固定してから検証する。
        viewModel.startTranscription(audioStream: AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.finish()
        })

        // 1. Add provisional to Part 1
        let segmentId = UUID()
        await viewModel.handleTranscriptSegment(TranscriptSegment(
            id: segmentId,
            sessionId: "s1",
            partId: part1Id,
            text: "認識中...",
            isFinal: false,
            startTime: 0.0,
            endTime: 0.0
        ))

        // 2. Simulate switching to Part 2 while transcription is "active"
        viewModel.currentPartIndex = 1

        // 3. Stop transcription
        // It should finalize Part 1 even though we are now on Part 2
        await viewModel.stopTranscription()

        // Wait a bit for the Task in stopTranscription to finish
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.sessionState.partStates[part1Id]?.transcript.count, 1)
        XCTAssertTrue(viewModel.sessionState.partStates[part1Id]?.transcript.first?.isFinal ?? false, "Part 1 should be finalized")
        XCTAssertEqual(viewModel.sessionState.partStates[part2Id]?.transcript.count ?? 0, 0, "Part 2 should be empty")
    }

    @MainActor
    func testDuplicateSegmentDetection() async {
        let viewModel = SessionViewModel()
        let partId = "p1"
        let session = BriefingSession(id: "s1", name: "S1", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 5, setting: "", rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "s1"

        // 1. Add first segment
        let segment1 = TranscriptSegment(
            id: UUID(),
            sessionId: "s1",
            partId: partId,
            text: "こんにちは世界",
            isFinal: true,
            startTime: 10.0,
            endTime: 12.0
        )
        await viewModel.handleTranscriptSegment(segment1)

        // 2. Add second segment with DIFFERENT ID but same text and close time
        let segment2 = TranscriptSegment(
            id: UUID(),
            sessionId: "s1",
            partId: partId,
            text: "こんにちは世界",
            isFinal: true,
            startTime: 10.1,
            endTime: 12.1
        )
        await viewModel.handleTranscriptSegment(segment2)

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 1, "Should merge duplicates even with different IDs")
        let merged = viewModel.sessionState.partStates[partId]?.transcript.first
        XCTAssertEqual(merged?.text, "こんにちは世界")
        XCTAssertEqual(merged?.startTime, 10.1, "Should have updated to latest segment values")

        // 3. Add same text but distant time
        let segment3 = TranscriptSegment(
            id: UUID(),
            sessionId: "s1",
            partId: partId,
            text: "こんにちは世界",
            isFinal: true,
            startTime: 20.0,
            endTime: 22.0
        )
        await viewModel.handleTranscriptSegment(segment3)

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 2, "Should not merge if time is distant")
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.last?.startTime, 20.0)

        // 4. Add slightly different text but close time
        let segment4 = TranscriptSegment(
            id: UUID(),
            sessionId: "s1",
            partId: partId,
            text: "こんにちは世界。",
            isFinal: true,
            startTime: 20.1,
            endTime: 22.1
        )
        await viewModel.handleTranscriptSegment(segment4)

        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.count, 2, "Should merge slightly different text (e.g. punctuation)")
        XCTAssertEqual(viewModel.sessionState.partStates[partId]?.transcript.last?.text, "こんにちは世界。", "Should have updated to latest segment text")
    }
}
