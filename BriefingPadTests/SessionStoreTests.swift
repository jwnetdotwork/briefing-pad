import XCTest
@testable import BriefingPad

final class SessionStoreTests: XCTestCase {
    var store: FileSessionStore!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = FileSessionStore(rootURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoadSession() async throws {
        let sessionId = "test-session"
        let partId = "part-1"

        let template = BriefingSession(id: sessionId, name: "Test", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 1, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])

        var partRun = PartRun(partId: partId)
        partRun.transcript = [
            TranscriptSegment(sessionId: sessionId, partId: partId, text: "Hello", isFinal: true, startTime: 0, endTime: 1)
        ]
        partRun.llmResults = [
            LLMResult(observationMatches: [], positiveMatches: [], sourceChunkId: UUID(), sourceChunkText: "Hello", sourceChunkStartTime: 0, sourceChunkEndTime: 1)
        ]
        partRun.finalSummary = FinalSummary(text: "Summary", adoptedItemIds: ["i1"], sourceLLMResultIds: [partRun.llmResults[0].id])
        partRun.elapsedTime = 10
        partRun.isFinished = true

        let savedSession = SavedSession(
            sessionId: sessionId,
            templateSnapshot: template,
            updatedAt: Date(),
            notionPageId: "page-123",
            partRuns: [partId: partRun]
        )

        try await store.saveSession(savedSession)

        let loaded = try await store.loadSession(sessionId: sessionId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionId, sessionId)
        XCTAssertEqual(loaded?.notionPageId, "page-123")
        XCTAssertEqual(loaded?.partRuns[partId]?.transcript.count, 1)
        XCTAssertEqual(loaded?.partRuns[partId]?.transcript[0].text, "Hello")
        XCTAssertEqual(loaded?.partRuns[partId]?.llmResults.count, 1)
        XCTAssertEqual(loaded?.partRuns[partId]?.finalSummary?.text, "Summary")
        XCTAssertEqual(loaded?.partRuns[partId]?.elapsedTime, 10)
        XCTAssertTrue(loaded?.partRuns[partId]?.isFinished ?? false)
    }

    func testDeleteSession() async throws {
        let sessionId = "test-session"
        let template = BriefingSession(id: sessionId, name: "Test", parts: [])
        let savedSession = SavedSession(sessionId: sessionId, templateSnapshot: template, updatedAt: Date(), partRuns: [:])

        try await store.saveSession(savedSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(sessionId).path))

        try await store.deleteSession(sessionId: sessionId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(sessionId).path))
    }

    func testDeleteSpecificData() async throws {
        let sessionId = "test-session"
        let partId = "part-1"
        let template = BriefingSession(id: sessionId, name: "Test", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 1, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])

        var partRun = PartRun(partId: partId)
        partRun.transcript = [TranscriptSegment(sessionId: sessionId, partId: partId, text: "H", isFinal: true, startTime: 0, endTime: 1)]
        partRun.llmResults = [LLMResult(observationMatches: [], positiveMatches: [], sourceChunkId: UUID(), sourceChunkText: "H", sourceChunkStartTime: 0, sourceChunkEndTime: 1)]
        partRun.finalSummary = FinalSummary(text: "S", adoptedItemIds: [], sourceLLMResultIds: [])

        let savedSession = SavedSession(sessionId: sessionId, templateSnapshot: template, updatedAt: Date(), partRuns: [partId: partRun])
        try await store.saveSession(savedSession)

        let partDir = tempDir.appendingPathComponent("\(sessionId)/parts/\(partId)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("transcript.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("llm_results.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("final_summary.json").path))

        try await store.deleteTranscript(sessionId: sessionId, partId: partId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("transcript.json").path))

        try await store.deleteLLMResults(sessionId: sessionId, partId: partId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("llm_results.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partDir.appendingPathComponent("final_summary.json").path))
    }

    func testAudioPersistence() async throws {
        let sessionId = "test-session"
        let partId = "part-1"
        let template = BriefingSession(id: sessionId, name: "Test", parts: [
            PartDefinition(id: partId, number: 1, title: "P1", durationMinutes: 1, setting: nil, rawMarkdown: "", learningPoints: [], observationItems: [], positiveItems: [])
        ])

        let recordingId = "run1"
        let audioURL = store.getAudioURL(sessionId: sessionId, partId: partId, recordingId: recordingId)
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "dummy audio".data(using: .utf8)?.write(to: audioURL)

        var partRun = PartRun(partId: partId)
        partRun.audioFileName = audioURL.lastPathComponent

        let savedSession = SavedSession(sessionId: sessionId, templateSnapshot: template, updatedAt: Date(), partRuns: [partId: partRun])
        try await store.saveSession(savedSession)

        let loaded = try await store.loadSession(sessionId: sessionId)
        XCTAssertEqual(loaded?.partRuns[partId]?.audioFileName, audioURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))

        try await store.deleteAudio(sessionId: sessionId, partId: partId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))

        let reloadedAfterDelete = try await store.loadSession(sessionId: sessionId)
        XCTAssertNil(reloadedAfterDelete?.partRuns[partId]?.audioFileName)
    }
}
