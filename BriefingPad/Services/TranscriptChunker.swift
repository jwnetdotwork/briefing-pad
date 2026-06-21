import Foundation

@MainActor
class TranscriptChunker {
    private let clock: Clock
    private let scheduler: Scheduler
    private let onFlush: (TranscriptChunk) -> Void

    private var currentSegments: [TranscriptSegment] = []
    private var chunkStartTime: Date?
    private let maxChunkDuration: TimeInterval = 15.0
    private let silenceThreshold: TimeInterval = 1.0
    private let maxCharacterCount: Int = 120

    @MainActor
    init(
        clock: Clock = RealClock(),
        scheduler: Scheduler? = nil,
        onFlush: @escaping (TranscriptChunk) -> Void
    ) {
        self.clock = clock
        self.scheduler = scheduler ?? RealScheduler()
        self.onFlush = onFlush
    }

    func processSegment(_ segment: TranscriptSegment) {
        guard segment.isFinal else { return }

        // If partId changes, flush existing chunk first
        if let first = currentSegments.first, first.partId != segment.partId {
            flush()
        }

        // 15s limit check: if existing chunk is already old, flush it before adding new segment
        if let startTime = chunkStartTime, clock.now.timeIntervalSince(startTime) >= maxChunkDuration {
            flush()
        }

        if currentSegments.isEmpty {
            chunkStartTime = clock.now
        }

        currentSegments.append(segment)

        // Character count check
        let currentText = currentSegments.map { $0.text }.joined(separator: " ")
        if currentText.count >= maxCharacterCount {
            flush()
            return
        }

        // Reset silence timer
        scheduler.schedule(after: silenceThreshold) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.flush()
            }
        }
    }

    func flush() {
        scheduler.cancel()

        guard !currentSegments.isEmpty else { return }

        let combinedText = currentSegments.map { $0.text }.joined(separator: " ")
        let trimmedText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedText.isEmpty {
            let chunk = TranscriptChunk(
                partId: currentSegments[0].partId,
                text: trimmedText,
                startTime: currentSegments.first!.startTime,
                endTime: currentSegments.last!.endTime
            )
            onFlush(chunk)
        }

        currentSegments.removeAll()
        chunkStartTime = nil
    }
}
