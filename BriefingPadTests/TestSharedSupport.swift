import Foundation
import XCTest
@testable import BriefingPad

@MainActor
func waitUntil(
    timeout: TimeInterval = 2.0,
    interval: UInt64 = 10_000_000, // 10ms
    message: String = "Wait timeout",
    condition: () -> Bool
) async throws {
    let start = Date()
    while !condition() {
        if Date().timeIntervalSince(start) > timeout {
            XCTFail(message)
            return
        }
        try await Task.sleep(nanoseconds: interval)
    }
}

final class MockClock: Clock, @unchecked Sendable {
    var now: Date = Date()
}

class MockSessionStore: SessionStoreProtocol {
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
func setupTestFixture(viewModel: SessionViewModel) -> String {
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
