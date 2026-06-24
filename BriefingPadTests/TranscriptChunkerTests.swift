import XCTest
@testable import BriefingPad

final class TranscriptChunkerTests: XCTestCase {
    class MutableClock: Clock {
        var now: Date = Date()
    }

    class TestScheduler: Scheduler {
        var lastAction: (@Sendable () -> Void)?
        var lastDuration: TimeInterval?
        func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void) {
            lastDuration = duration
            lastAction = action
        }
        func cancel() {
            lastAction = nil
            lastDuration = nil
        }
    }

    @MainActor
    func testSilenceThreshold() async {
        let expectation = XCTestExpectation(description: "Chunk should be flushed after silence")
        var flushedChunks: [TranscriptChunk] = []
        let scheduler = TestScheduler()
        let chunker = TranscriptChunker(clock: RealClock(), scheduler: scheduler) { chunk in
            flushedChunks.append(chunk)
            expectation.fulfill()
        }

        let segment = TranscriptSegment(sessionId: "s1", partId: "p1", text: "Hello", isFinal: true, startTime: 100, endTime: 101)
        chunker.processSegment(segment)

        XCTAssertEqual(flushedChunks.count, 0)
        XCTAssertNotNil(scheduler.lastAction)

        // Trigger silence
        scheduler.lastAction?()

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.text, "Hello")
        XCTAssertEqual(flushedChunks.first?.startTime, 100)
        XCTAssertEqual(flushedChunks.first?.endTime, 101)
    }

    @MainActor
    func testMaxDuration() async {
        let expectation1 = XCTestExpectation(description: "First chunk should be flushed by max duration")
        let expectation2 = XCTestExpectation(description: "Second chunk should be flushed by silence")
        var flushedChunks: [TranscriptChunk] = []
        let scheduler = TestScheduler()
        let clock = MutableClock()
        let chunker = TranscriptChunker(clock: clock, scheduler: scheduler) { chunk in
            flushedChunks.append(chunk)
            if flushedChunks.count == 1 {
                expectation1.fulfill()
            } else if flushedChunks.count == 2 {
                expectation2.fulfill()
            }
        }

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "First", isFinal: true, startTime: 10, endTime: 11))
        XCTAssertEqual(flushedChunks.count, 0)

        clock.now += 16
        // This segment arrives after 15s, so the PREVIOUS chunk ("First") should be flushed immediately.
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "Second", isFinal: true, startTime: 26, endTime: 27))

        await fulfillment(of: [expectation1], timeout: 1.0)
        XCTAssertEqual(flushedChunks.first?.text, "First")

        // Finalize by silence to check second chunk
        scheduler.lastAction?()
        await fulfillment(of: [expectation2], timeout: 1.0)

        XCTAssertEqual(flushedChunks.count, 2)
        XCTAssertEqual(flushedChunks.last?.text, "Second")
    }

    @MainActor
    func testCharacterLimit() async {
        var flushedChunks: [TranscriptChunk] = []
        let chunker = TranscriptChunker(clock: RealClock(), scheduler: RealScheduler(), onFlush: { flushedChunks.append($0) })

        let longText = String(repeating: "A", count: 121)
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: longText, isFinal: true, startTime: 10, endTime: 20))

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.text.count, 121)
    }

    @MainActor
    func testPartChangeFlushes() async {
        var flushedChunks: [TranscriptChunk] = []
        let chunker = TranscriptChunker(clock: RealClock(), scheduler: RealScheduler(), onFlush: { flushedChunks.append($0) })

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "Part 1", isFinal: true, startTime: 10, endTime: 11))
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p2", text: "Part 2", isFinal: true, startTime: 12, endTime: 13))

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.partId, "p1")
        XCTAssertEqual(flushedChunks.first?.text, "Part 1")
    }

    @MainActor
    func testEmptyAfterTrimDoesNotFlush() async {
        let expectation = XCTestExpectation(description: "Chunk should NOT be flushed")
        expectation.isInverted = true
        let scheduler = TestScheduler()
        let chunker = TranscriptChunker(clock: RealClock(), scheduler: scheduler) { _ in
            expectation.fulfill()
        }

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "   ", isFinal: true, startTime: 10, endTime: 11))
        scheduler.lastAction?()

        await fulfillment(of: [expectation], timeout: 0.1)
    }
}
