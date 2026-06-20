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
        var flushedChunks: [TranscriptChunk] = []
        let scheduler = TestScheduler()
        let chunker = TranscriptChunker(scheduler: scheduler) { chunk in
            flushedChunks.append(chunk)
        }

        let segment = TranscriptSegment(sessionId: "s1", partId: "p1", text: "Hello", isFinal: true, startTime: 100, endTime: 101)
        chunker.processSegment(segment)

        XCTAssertEqual(flushedChunks.count, 0)
        XCTAssertNotNil(scheduler.lastAction)

        // Trigger silence
        scheduler.lastAction?()

        // Wait for @MainActor Task
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.text, "Hello")
        XCTAssertEqual(flushedChunks.first?.startTime, 100)
        XCTAssertEqual(flushedChunks.first?.endTime, 101)
    }

    @MainActor
    func testMaxDuration() async {
        var flushedChunks: [TranscriptChunk] = []
        let scheduler = TestScheduler()
        let clock = MutableClock()
        let chunker = TranscriptChunker(clock: clock, scheduler: scheduler) { chunk in
            flushedChunks.append(chunk)
        }

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "First", isFinal: true, startTime: 10, endTime: 11))
        XCTAssertEqual(flushedChunks.count, 0)

        clock.now += 16
        // This segment arrives after 15s, so the PREVIOUS chunk ("First") should be flushed immediately.
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "Second", isFinal: true, startTime: 26, endTime: 27))

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.text, "First")

        // Finalize by silence to check second chunk
        scheduler.lastAction?()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(flushedChunks.count, 2)
        XCTAssertEqual(flushedChunks.last?.text, "Second")
    }

    @MainActor
    func testCharacterLimit() async {
        var flushedChunks: [TranscriptChunk] = []
        let chunker = TranscriptChunker(onFlush: { flushedChunks.append($0) })

        let longText = String(repeating: "A", count: 121)
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: longText, isFinal: true, startTime: 10, endTime: 20))

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.text.count, 121)
    }

    @MainActor
    func testPartChangeFlushes() async {
        var flushedChunks: [TranscriptChunk] = []
        let chunker = TranscriptChunker(onFlush: { flushedChunks.append($0) })

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "Part 1", isFinal: true, startTime: 10, endTime: 11))
        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p2", text: "Part 2", isFinal: true, startTime: 12, endTime: 13))

        XCTAssertEqual(flushedChunks.count, 1)
        XCTAssertEqual(flushedChunks.first?.partId, "p1")
        XCTAssertEqual(flushedChunks.first?.text, "Part 1")
    }

    @MainActor
    func testEmptyAfterTrimDoesNotFlush() async {
        var flushedChunks: [TranscriptChunk] = []
        let scheduler = TestScheduler()
        let chunker = TranscriptChunker(scheduler: scheduler) { flushedChunks.append($0) }

        chunker.processSegment(TranscriptSegment(sessionId: "s1", partId: "p1", text: "   ", isFinal: true, startTime: 10, endTime: 11))
        scheduler.lastAction?()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(flushedChunks.count, 0)
    }
}
