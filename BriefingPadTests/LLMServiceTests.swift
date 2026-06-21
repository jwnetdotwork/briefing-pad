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
        XCTAssertTrue(userPrompt.contains(fullTranscript))
        XCTAssertTrue(userPrompt.contains(newChunk))
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
