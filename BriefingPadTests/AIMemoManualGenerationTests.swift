import XCTest
@testable import BriefingPad

@MainActor
final class AIMemoManualGenerationTests: XCTestCase {

    func testManualRegeneration_DoesNotMarkFinished() async {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            clock: MockClock()
        )

        let partId = viewModel.currentPart?.id ?? ""
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true)

        // 1. Manually regenerate
        viewModel.regenerateAIMemo()

        // Wait for task to complete (since regenerateAIMemo uses Task internally)
        // We can poll isGeneratingAIMemo or just wait a bit.
        // Since it's a mock with 0 delay, it should be fast.
        var limit = 0
        while viewModel.isGeneratingAIMemo && limit < 10 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            limit += 1
        }

        // 2. Verify aiMemo is populated but isFinished is still false
        XCTAssertFalse(viewModel.sessions[0].parts[0].aiMemo.isEmpty)
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true)
    }

    func testNotionContentFormat() async {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = SpyNotionService()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            clock: MockClock()
        )

        // Setup part data
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
            viewModel.sessions[0].parts[0] = part
        }

        await viewModel.finishPart()

        // Verify Notion content format
        guard let syncedContent = mockNotion.lastSyncedContent else {
            XCTFail("Content was not synced to Notion")
            return
        }

        XCTAssertTrue(syncedContent.contains("◎ 良かった点候補"))
        XCTAssertTrue(syncedContent.contains("・\(viewModel.sessions[0].parts[0].positiveItems[0].text) (PosEvidence)"))
        XCTAssertTrue(syncedContent.contains("👀 観察メモ"))
        XCTAssertTrue(syncedContent.contains("・\(viewModel.sessions[0].parts[0].observationItems[0].text) (ObsEvidence)"))
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
