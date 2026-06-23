import XCTest
@testable import BriefingPad

final class LLMServiceTests: XCTestCase {

    func testPromptBuilder() {
        let partInfo = PartDefinition(
            id: "test-part",
            number: 1,
            title: "Test Part",
            durationMinutes: 5,
            setting: "Test Setting",
            rawMarkdown: "",
            learningPoints: [LearningPoint(id: "lp1", text: "Point 1")],
            observationItems: [ObservationItem(id: "obs1", text: "Obs 1")],
            positiveItems: [PositiveItem(id: "pos1", text: "Pos 1")]
        )

        let fullTranscript = "Full transcript text."
        let newChunk = "New chunk text."

        let systemPrompt = PromptBuilder.buildSystemPrompt()
        let userPrompt = PromptBuilder.buildUserPrompt(
            fullTranscript: fullTranscript,
            newChunk: newChunk,
            partInfo: partInfo
        )

        XCTAssertTrue(systemPrompt.contains("JSON"))
        XCTAssertTrue(userPrompt.contains("Test Part"))
        XCTAssertTrue(userPrompt.contains("Test Setting"))
        XCTAssertTrue(userPrompt.contains("Point 1"))
        XCTAssertTrue(userPrompt.contains("obs1"))
        XCTAssertTrue(userPrompt.contains("pos1"))
        XCTAssertTrue(userPrompt.contains("状態: hidden (未判定)"))
        XCTAssertTrue(userPrompt.contains(fullTranscript))
        XCTAssertTrue(userPrompt.contains(newChunk))
    }

    func testPromptBuilderWithCumulativeState() {
        var partInfo = PartDefinition(
            id: "test-part",
            number: 1,
            title: "Test Part",
            durationMinutes: 5,
            setting: "Test Setting",
            rawMarkdown: "",
            learningPoints: [LearningPoint(id: "lp1", text: "Point 1")],
            observationItems: [ObservationItem(id: "obs1", text: "Obs 1")],
            positiveItems: [PositiveItem(id: "pos1", text: "Pos 1")]
        )

        // Set some cumulative state
        partInfo.analysisState.observationItemStates["obs1"] = AnalysisItemState(
            confidence: 0.8,
            shortEvidence: "Found evidence for obs1",
            status: .candidate,
            lastUpdatedAt: Date()
        )
        partInfo.analysisState.positiveItemStates["pos1"] = AnalysisItemState(
            confidence: 1.0,
            shortEvidence: "Strong evidence for pos1",
            status: .strong,
            lastUpdatedAt: Date()
        )

        let userPrompt = PromptBuilder.buildUserPrompt(
            fullTranscript: "Full transcript.",
            newChunk: "New chunk.",
            partInfo: partInfo
        )

        XCTAssertTrue(userPrompt.contains("これまでの判定結果"))
        XCTAssertTrue(userPrompt.contains("id: obs1, 内容: Obs 1, 状態: candidate, 確信度: 0.8, 根拠: Found evidence for obs1"))
        XCTAssertTrue(userPrompt.contains("id: pos1, 内容: Pos 1, 状態: strong, 確信度: 1.0, 根拠: Strong evidence for pos1"))
    }

    func testOneLinerPromptBuilder() {
        let partInfo = PartDefinition(
            id: "test-part",
            number: 1,
            title: "Test Part",
            durationMinutes: 5,
            setting: "Test Setting",
            rawMarkdown: "",
            learningPoints: [LearningPoint(id: "lp1", text: "Point 1")],
            observationItems: [],
            positiveItems: []
        )

        let fullTranscript = "Full transcript text."
        let positives = [SummarizedItem(text: "Good point", evidence: "He smiled")]
        let observations = [SummarizedItem(text: "Observed", evidence: "He sat down")]

        let systemPrompt = PromptBuilder.buildOneLinerSystemPrompt()
        let userPrompt = PromptBuilder.buildOneLinerUserPrompt(
            partInfo: partInfo,
            fullTranscript: fullTranscript,
            positives: positives,
            observations: observations
        )

        XCTAssertTrue(systemPrompt.contains("箇条書き"))
        XCTAssertTrue(userPrompt.contains("Test Part"))
        XCTAssertTrue(userPrompt.contains("Point 1"))
        XCTAssertTrue(userPrompt.contains("Good point"))
        XCTAssertTrue(userPrompt.contains("He smiled"))
        XCTAssertTrue(userPrompt.contains("Observed"))
        XCTAssertTrue(userPrompt.contains("He sat down"))
        XCTAssertTrue(userPrompt.contains(fullTranscript))
    }

    func testAnalysisResultParsing() throws {
        let json = """
        {
          "observationMatches": [
            { "itemId": "obs1", "confidence": 0.9, "shortEvidence": "found obs1" }
          ],
          "positiveMatches": [
            { "itemId": "pos1", "confidence": 0.7, "shortEvidence": "found pos1" }
          ]
        }
        """

        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(AnalysisResult.self, from: data)

        XCTAssertEqual(result.observationMatches.count, 1)
        XCTAssertEqual(result.observationMatches[0].itemId, "obs1")
        XCTAssertEqual(result.observationMatches[0].confidence, 0.9)
        XCTAssertEqual(result.observationMatches[0].shortEvidence, "found obs1")

        XCTAssertEqual(result.positiveMatches.count, 1)
        XCTAssertEqual(result.positiveMatches[0].itemId, "pos1")
        XCTAssertEqual(result.positiveMatches[0].confidence, 0.7)
        XCTAssertEqual(result.positiveMatches[0].shortEvidence, "found pos1")
    }
}
