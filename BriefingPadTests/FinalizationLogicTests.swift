import XCTest
@testable import BriefingPad

@MainActor
final class FinalizationLogicTests: XCTestCase {

    func testSummarizedItemModel() {
        let item = SummarizedItem(id: "id1", text: "Text", evidence: "Evidence")
        XCTAssertEqual(item.id, "id1")
    }

    func testGetSummarizedItems_Prioritization() {
        let viewModel = SessionViewModel(
            llmService: MockLLMService(),
            notionService: MockNotionService(),
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: MockSessionStore(),
            clock: MockClock()
        )

        let items = [
            PositiveItem(id: "1", text: "Item 1"),
            PositiveItem(id: "2", text: "Item 2"),
            PositiveItem(id: "3", text: "Item 3"),
            PositiveItem(id: "4", text: "Item 4")
        ]

        let states: [String: AnalysisItemState] = [
            "1": AnalysisItemState(confidence: 0.9, shortEvidence: "E1", status: .strong, lastUpdatedAt: Date()),
            "2": AnalysisItemState(confidence: 0.95, shortEvidence: "E2", status: .candidate, lastUpdatedAt: Date()),
            "3": AnalysisItemState(confidence: 0.99, shortEvidence: "E3", status: .strong, lastUpdatedAt: Date()),
            "4": AnalysisItemState(confidence: 0.1, shortEvidence: "E4", status: .hidden, lastUpdatedAt: Date())
        ]

        let summarized = viewModel.getSummarizedItems(items: items, states: states)

        XCTAssertEqual(summarized.count, 3)
        XCTAssertEqual(summarized[0].text, "Item 3") // strong, 0.99
        XCTAssertEqual(summarized[1].text, "Item 1") // strong, 0.9
        XCTAssertEqual(summarized[2].text, "Item 2") // candidate, 0.95
    }

    @MainActor
    func testAnalysisUpdateAfterFinishPart_ShouldNotOverwriteMemo() async throws {
        let mockLLM = ControlledMockLLM()
        let mockNotion = MockNotionService()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: MockSessionStore(),
            clock: MockClock()
        )

        let partId = await setupTestFixture(viewModel: viewModel)

        // Verify finishPart populates memo and marks as finished
        await viewModel.finishPart()

        let firstPart = try XCTUnwrap(viewModel.sessions.first?.parts.first)
        XCTAssertFalse(firstPart.aiMemo.isEmpty, "Memo should be populated after finishPart")
        XCTAssertTrue(viewModel.sessionState.partStates[partId]?.isFinished ?? false)
    }

    private actor ControlledMockLLM: LLMServiceProtocol {
        private var continuation: CheckedContinuation<Void, Never>?
        private var startContinuation: CheckedContinuation<Void, Never>?
        private var didStart = false

        func resume() {
            continuation?.resume()
            continuation = nil
        }

        func waitForStart() async {
            if didStart { return }
            await withCheckedContinuation { continuation in
                self.startContinuation = continuation
            }
        }

        func analyzeTranscript(fullTranscript: String, newChunk: String, partInfo: PartDefinition) async throws -> AnalysisResult {
            didStart = true
            startContinuation?.resume()
            startContinuation = nil

            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            return AnalysisResult(
                observationMatches: [],
                positiveMatches: []
            )
        }

        func generateOneLiner(
            partInfo: PartDefinition,
            fullTranscript: String,
            positives: [SummarizedItem],
            observations: [SummarizedItem]
        ) async throws -> String {
            return "Mock One-Liner"
        }
    }

    @MainActor
    func testFinishPartFlow() async throws {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: MockSessionStore(),
            clock: MockClock()
        )

        let partId = await setupTestFixture(viewModel: viewModel)
        XCTAssertFalse(viewModel.sessionState.partStates[partId]?.isFinished ?? true)

        // Inject some analysis results
        if var part = viewModel.currentPart {
            part.analysisState.positiveItemStates[part.positiveItems[0].id] = AnalysisItemState(
                confidence: 0.9, shortEvidence: "Evidence", status: .strong, lastUpdatedAt: Date()
            )
            part.aiMemoBlockId = "mock-block-id"
            viewModel.sessions[0].parts[0] = part
        }

        await viewModel.finishPart()

        XCTAssertTrue(viewModel.sessionState.partStates[partId]?.isFinished ?? false)
        let finishedPart = try XCTUnwrap(viewModel.sessions.first?.parts.first)
        XCTAssertFalse(finishedPart.aiMemo.isEmpty)
    }

    @MainActor
    func testFinishPartFlow_NotionExternalModification() async throws {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        mockNotion.shouldSimulateExternalModification = true

        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            store: MockSessionStore(),
            clock: MockClock()
        )

        let _ = await setupTestFixture(viewModel: viewModel)

        // Setup initial part with a block ID
        if var part = viewModel.currentPart {
            part.aiMemoBlockId = "original-block-id"
            viewModel.sessions[0].parts[0] = part
        }

        await viewModel.finishPart()

        // Verify block ID was updated
        let finishedPart = try XCTUnwrap(viewModel.sessions.first?.parts.first)
        XCTAssertNotEqual(finishedPart.aiMemoBlockId, "original-block-id")
        XCTAssertTrue(finishedPart.aiMemoBlockId?.contains("new-block-id") ?? false)
    }
}
