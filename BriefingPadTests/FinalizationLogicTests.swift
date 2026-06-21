import XCTest
@testable import BriefingPad

@MainActor
final class FinalizationLogicTests: XCTestCase {

    func testGetSummarizedItems_Prioritization() {
        let viewModel = SessionViewModel(
            llmService: MockLLMService(),
            notionService: MockNotionService(),
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
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

        XCTAssertEqual(summarized.count, 2)
        XCTAssertEqual(summarized[0].text, "Item 3") // strong, 0.99
        XCTAssertEqual(summarized[1].text, "Item 1") // strong, 0.9
    }

    func testFormatFinalMemo_Full() {
        let viewModel = SessionViewModel()

        let positives = [
            SessionViewModel.SummarizedItem(text: "P1", evidence: "PE1"),
            SessionViewModel.SummarizedItem(text: "P2", evidence: "PE2")
        ]
        let observations = [
            SessionViewModel.SummarizedItem(text: "O1", evidence: "OE1")
        ]
        let oneLiner = "Excellent work!"

        let memo = viewModel.formatFinalMemo(positives: positives, observations: observations, oneLiner: oneLiner)

        let expected = """
        ◎ 短評で使えそう
        - P1: PE1
        - P2: PE2

        👀 根拠になりそうな観察
        - O1: OE1

        💡 言えそうな一言
        Excellent work!
        """
        XCTAssertEqual(memo, expected)
    }

    func testFormatFinalMemo_MissingSections() {
        let viewModel = SessionViewModel()

        let positives: [SessionViewModel.SummarizedItem] = []
        let observations = [
            SessionViewModel.SummarizedItem(text: "O1", evidence: "OE1")
        ]
        let oneLiner = ""

        let memo = viewModel.formatFinalMemo(positives: positives, observations: observations, oneLiner: oneLiner)

        let expected = """
        👀 根拠になりそうな観察
        - O1: OE1
        """
        XCTAssertEqual(memo, expected)
    }

    @MainActor
    func testFinishPartFlow() async {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            clock: MockClock()
        )

        // Initial state
        let partId = viewModel.currentPart?.id ?? ""
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
        XCTAssertFalse(viewModel.sessions[0].parts[0].aiMemo.isEmpty)
        XCTAssertTrue(viewModel.sessions[0].parts[0].aiMemo.contains("◎ 短評で使えそう"))
        XCTAssertTrue(viewModel.sessions[0].parts[0].aiMemo.contains("💡 言えそうな一言"))
    }

    @MainActor
    func testFinishPartFlow_NotionExternalModification() async {
        let mockLLM = MockLLMService(delayNanoseconds: 0)
        let mockNotion = MockNotionService()
        mockNotion.shouldSimulateExternalModification = true

        let viewModel = SessionViewModel(
            llmService: mockLLM,
            notionService: mockNotion,
            transcriptionService: MockSpeechTranscriptionService(),
            micService: MicrophoneService(),
            clock: MockClock()
        )

        // Setup initial part with a block ID
        if var part = viewModel.currentPart {
            part.aiMemoBlockId = "original-block-id"
            viewModel.sessions[0].parts[0] = part
        }

        await viewModel.finishPart()

        // Verify block ID was updated
        XCTAssertNotEqual(viewModel.sessions[0].parts[0].aiMemoBlockId, "original-block-id")
        XCTAssertTrue(viewModel.sessions[0].parts[0].aiMemoBlockId?.contains("new-block-id") ?? false)
    }
}

class MockClock: Clock {
    var now: Date = Date()
}
