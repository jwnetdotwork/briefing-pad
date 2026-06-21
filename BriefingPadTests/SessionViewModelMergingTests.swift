import XCTest
@testable import BriefingPad

final class SessionViewModelMergingTests: XCTestCase {

    @MainActor
    func testMergingLogic() async {
        let obs1 = ObservationItem(id: "obs1", text: "Obs 1")
        let pos1 = PositiveItem(id: "pos1", text: "Pos 1")
        let partInfo = PartDefinition(
            id: "part1",
            number: 1,
            title: "Part 1",
            durationMinutes: 10,
            setting: nil,
            rawMarkdown: "",
            learningPoints: [],
            observationItems: [obs1],
            positiveItems: [pos1]
        )

        let session = BriefingSession(id: "session1", name: "Session 1", parts: [partInfo])

        // Mock DataStore to return our session
        // (In a real test we'd inject a mock data store, but here we'll test the merging logic via direct access if possible,
        // or by inspecting the view model state after processing)

        let mockLLM = MockLLMServiceWithResult()
        let viewModel = SessionViewModel(llmService: mockLLM)
        viewModel.sessions = [session]
        viewModel.selectedSessionId = "session1"

        // Initial state should be hidden
        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.status, .hidden)

        // 1. First update: strong
        mockLLM.result = AnalysisResult(
            observationMatches: [ItemMatch(itemId: "obs1", confidence: 0.9, shortEvidence: "strong evidence")],
            positiveMatches: []
        )

        await viewModel.processTranscriptChunk("chunk 1")

        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.status, .strong)
        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.confidence, 0.9)

        // 2. Second update: candidate (should stay strong)
        mockLLM.result = AnalysisResult(
            observationMatches: [ItemMatch(itemId: "obs1", confidence: 0.7, shortEvidence: "candidate evidence")],
            positiveMatches: []
        )

        await viewModel.processTranscriptChunk("chunk 2")

        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.status, .strong)
        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.confidence, 0.9)

        // 2b. Same status, higher confidence should update
        mockLLM.result = AnalysisResult(
            observationMatches: [ItemMatch(itemId: "obs1", confidence: 0.95, shortEvidence: "even stronger evidence")],
            positiveMatches: []
        )

        await viewModel.processTranscriptChunk("chunk 2b")

        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.status, .strong)
        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.confidence, 0.95)

        // 3. Third update: explicit downgrade (confidence < 0.6)
        mockLLM.result = AnalysisResult(
            observationMatches: [ItemMatch(itemId: "obs1", confidence: 0.3, shortEvidence: "not found")],
            positiveMatches: []
        )

        await viewModel.processTranscriptChunk("chunk 3")

        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.status, .hidden)
        XCTAssertEqual(viewModel.currentPart?.analysisState.observationItemStates["obs1"]?.confidence, 0.3)
    }
}

class MockLLMServiceWithResult: LLMServiceProtocol {
    var result: AnalysisResult = AnalysisResult(observationMatches: [], positiveMatches: [])

    func analyzeTranscript(fullTranscript: String, newChunk: String, partInfo: PartDefinition) async throws -> AnalysisResult {
        return result
    }
}
