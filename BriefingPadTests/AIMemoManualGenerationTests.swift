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
        let partId = await setupTestFixture(viewModel: viewModel)

        // Ensure initial state is not finished
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true)
        XCTAssertTrue(viewModel.sessions[0].parts[0].aiMemo.isEmpty)

        // 1. Manually regenerate
        viewModel.regenerateAIMemo()

        // Wait for aiMemo to be populated and generation flag to be false
        try await waitUntil(message: "aiMemo should be populated and generation complete") {
            !(viewModel.sessions.first?.parts.first?.aiMemo.isEmpty ?? true) && !viewModel.isGeneratingAIMemo
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
        let _ = await setupTestFixture(viewModel: viewModel)

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
}
