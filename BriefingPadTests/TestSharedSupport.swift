import Foundation
import XCTest
import Combine
import AVFoundation
@testable import BriefingPad

@MainActor
func waitUntil(
    timeout: TimeInterval = 2.0,
    interval: UInt64 = 10_000_000, // 10ms
    message: String = "Wait timeout",
    file: StaticString = #file,
    line: UInt = #line,
    condition: () -> Bool
) async throws {
    let start = Date()
    while !condition() {
        if Date().timeIntervalSince(start) > timeout {
            XCTFail(message, file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: interval)
    }
}

final class MockClock: Clock, @unchecked Sendable {
    var now: Date = Date()
}

class MockSessionStore: SessionStoreProtocol {
    func deletePart(sessionId: String, partId: String) async throws {
    }
    
    func listSessions() async throws -> [String] { return [] }
    func loadSession(sessionId: String) async throws -> SavedSession? { return nil }
    func saveSession(_ session: SavedSession) async throws {}
    func deleteSession(sessionId: String) async throws {}
    func deleteAudio(sessionId: String, partId: String) async throws {}
    func deleteTranscript(sessionId: String, partId: String) async throws {}
    func deleteLLMResults(sessionId: String, partId: String) async throws {}
    func getAudioURL(sessionId: String, partId: String, recordingId: String) -> URL {
        return URL(fileURLWithPath: "/tmp/audio.m4a")
    }
    func getPartDirectory(sessionId: String, partId: String) -> URL {
        return URL(fileURLWithPath: "/tmp")
    }
}

@MainActor
@discardableResult
func setupTestFixture(viewModel: SessionViewModel) async throws -> String {
    // Wait for bootstrap to complete
    try await waitUntil(message: "ViewModel should be bootstrapped") {
        viewModel.isBootstrapped
    }

    let pos1 = PositiveItem(id: "pos1", text: "Positive 1")
    let obs1 = ObservationItem(id: "obs1", text: "Observation 1")
    let part1 = PartDefinition(
        id: "part1",
        number: 1,
        title: "Part 1",
        durationMinutes: 5,
        setting: "Setting 1",
        rawMarkdown: "Raw Markdown",
        learningPoints: [],
        observationItems: [obs1],
        positiveItems: [pos1]
    )
    let session = BriefingSession(id: "s1", name: "Session 1", parts: [part1])

    viewModel.sessions = [session]
    viewModel.selectedSessionId = "s1"
    viewModel.currentPartIndex = 0

    var partState = PartState()
    partState.transcript = [
        TranscriptSegment(sessionId: "s1", partId: "part1", text: "Hello", isFinal: true, startTime: 0, endTime: 1)
    ]
    partState.isFinished = false
    viewModel.sessionState.partStates["part1"] = partState

    return "part1"
}

final class MockMicrophoneService: ObservableObject, MicrophoneServiceProtocol {
    @Published var status: MicrophoneStatus = .idle
    @Published var audioLevel: AudioLevel = .silent

    var statusPublisher: AnyPublisher<MicrophoneStatus, Never> {
        $status.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<AudioLevel, Never> {
        $audioLevel.eraseToAnyPublisher()
    }

    var startRecordingCalled = false
    var stopRecordingCalled = false
    var cancelPendingOperationsAndStopCalled = false
    var createAudioBufferStreamCalled = false

    private var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func createAudioBufferStream(runID: String? = nil) -> AsyncStream<AVAudioPCMBuffer> {
        createAudioBufferStreamCalled = true
        return AsyncStream { [weak self] continuation in
            self?.audioBufferContinuation = continuation
        }
    }

    func startRecording(audioFileURL: URL? = nil, runID: String? = nil) {
        startRecordingCalled = true
    }

    func stopRecording() {
        stopRecordingCalled = true
        status = .idle
        audioLevel = .silent
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
    }

    func cancelPendingOperationsAndStop() {
        cancelPendingOperationsAndStopCalled = true
        stopRecording()
    }
}

@MainActor
extension SessionViewModel {
    convenience init(
        llmService: LLMServiceProtocol? = nil,
        notionService: NotionServiceProtocol? = nil,
        transcriptionService: SpeechTranscribing? = nil,
        store: SessionStoreProtocol? = nil,
        clock: Clock? = nil,
        scheduler: BriefingPad.Scheduler? = nil
    ) {
        self.init(
            llmService: llmService,
            notionService: notionService,
            transcriptionService: transcriptionService,
            micService: MockMicrophoneService(),
            store: store,
            clock: clock,
            scheduler: scheduler
        )
    }
}
