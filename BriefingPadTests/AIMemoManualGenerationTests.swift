import XCTest
import AVFoundation
@testable import BriefingPad

@MainActor
final class AIMemoManualGenerationTests: XCTestCase {

    func testManualRegeneration_DoesNotMarkFinished() async throws {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        let mockStore = MockSessionStore()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: mockStore,
            clock: MockClock()
        )

        // Setup fixture
        let partId = setupFixture(viewModel: viewModel)

        // Ensure initial state is not finished
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true)
        XCTAssertTrue(viewModel.sessions[0].parts[0].aiMemo.isEmpty)

        // 1. Manually regenerate
        viewModel.regenerateAIMemo()

        // Wait for aiMemo to be populated (indicating generation is complete)
        let timeout = Date().addingTimeInterval(5.0)
        while (viewModel.sessions.first?.parts.first?.aiMemo.isEmpty ?? true) && Date() < timeout {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // 2. Verify aiMemo is populated but isFinished is still false
        let updatedPart = try XCTUnwrap(viewModel.sessions.first?.parts.first)
        XCTAssertFalse(updatedPart.aiMemo.isEmpty, "aiMemo should be populated after regeneration")
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true, "Part should not be marked as finished after manual regeneration")
    }

    func testNotionContentFormat() async throws {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = SpyNotionService()
        let mockStore = MockSessionStore()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: mockStore,
            clock: MockClock()
        )

        // Setup fixture
        let _ = setupFixture(viewModel: viewModel)

        // Additional setup for Notion sync
        if var part = viewModel.currentPart {
            part.aiMemoBlockId = "mock-block"
            // Add a positive item match
            let posId = part.positiveItems[0].id
            part.analysisState.positiveItemStates[posId] = AnalysisItemState(
                confidence: 0.9,
                shortEvidence: " (PosEvidence)",
                status: .strong,
                lastUpdatedAt: Date()
            )
            // Add an observation match
            let obsId = part.observationItems[0].id
            part.analysisState.observationItemStates[obsId] = AnalysisItemState(
                confidence: 0.8,
                shortEvidence: " (ObsEvidence)",
                status: .candidate,
                lastUpdatedAt: Date()
            )

            // Persist changes to the viewModel's sessions array
            if let sIdx = viewModel.sessions.firstIndex(where: { $0.id == viewModel.selectedSessionId }) {
                viewModel.sessions[sIdx].parts[viewModel.currentPartIndex] = part
            }
        }

        await viewModel.finishPart()

        // Verify Notion content format
        guard let syncedContent = mockNotion.lastSyncedContent else {
            XCTFail("Content was not synced to Notion")
            return
        }

        XCTAssertTrue(syncedContent.contains("◎ 良かった点候補"))
        XCTAssertTrue(syncedContent.contains("- \(viewModel.sessions[0].parts[0].positiveItems[0].text) (PosEvidence)"))
        XCTAssertTrue(syncedContent.contains("👀 観察メモ"))
        XCTAssertTrue(syncedContent.contains("- \(viewModel.sessions[0].parts[0].observationItems[0].text) (ObsEvidence)"))
        XCTAssertTrue(syncedContent.contains("🤖 コメント素材"))
        XCTAssertTrue(syncedContent.contains("素晴らしい対応でした"))
    }

    @discardableResult
    private func setupFixture(viewModel: SessionViewModel) -> String {
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

    private class SpyNotionService: NotionServiceProtocol {
        var lastSyncedContent: String?

        func upsertAIMemo(
            blockId: String,
            content: String,
            expectedLastEditedTime: String?,
            expectedContentHash: String?
        ) async throws -> NotionUpdateResult {
            lastSyncedContent = content
            return .success(lastEditedTime: "now", contentHash: "hash")
        }
    }

    private class MockSessionStore: SessionStoreProtocol {
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
}
