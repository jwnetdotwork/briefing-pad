import XCTest
@testable import BriefingPad

@MainActor
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
        let locale = "ja-JP"

        let systemPrompt = PromptBuilder.buildSystemPrompt(localeIdentifier: locale)
        let userPrompt = PromptBuilder.buildUserPrompt(
            fullTranscript: fullTranscript,
            newChunk: newChunk,
            partInfo: partInfo,
            localeIdentifier: locale
        )

        XCTAssertTrue(systemPrompt.contains("JSON"))
        XCTAssertTrue(systemPrompt.contains("Japanese"))
        XCTAssertTrue(userPrompt.contains("Test Part"))
        XCTAssertTrue(userPrompt.contains("Test Setting"))
        XCTAssertTrue(userPrompt.contains("Point 1"))
        XCTAssertTrue(userPrompt.contains("obs1"))
        XCTAssertTrue(userPrompt.contains("pos1"))
        XCTAssertTrue(userPrompt.contains("Status: hidden (unjudged)"))
        XCTAssertTrue(userPrompt.contains(fullTranscript))
        XCTAssertTrue(userPrompt.contains(newChunk))
        XCTAssertTrue(userPrompt.contains("Japanese"))

        // English headers
        XCTAssertTrue(userPrompt.contains("## Current Part Information"))
        XCTAssertTrue(userPrompt.contains("## Previous Results: Observation Items"))
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
            partInfo: partInfo,
            localeIdentifier: "ja-JP"
        )

        XCTAssertTrue(userPrompt.contains("Previous Results"))

        // Robust assertions for cumulative state
        XCTAssertTrue(userPrompt.contains("id: obs1"))
        XCTAssertTrue(userPrompt.contains("Content: Obs 1"))
        XCTAssertTrue(userPrompt.contains("Status: candidate"))
        XCTAssertTrue(userPrompt.contains("Evidence: Found evidence for obs1"))

        XCTAssertTrue(userPrompt.contains("id: pos1"))
        XCTAssertTrue(userPrompt.contains("Content: Pos 1"))
        XCTAssertTrue(userPrompt.contains("Status: strong"))
        XCTAssertTrue(userPrompt.contains("Evidence: Strong evidence for pos1"))
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
        let positives = [SummarizedItem(id: "pos1", text: "Good point", evidence: "He smiled")]
        let observations = [SummarizedItem(id: "obs1", text: "Observed", evidence: "He sat down")]
        let locale = "en-US"

        let systemPrompt = PromptBuilder.buildOneLinerSystemPrompt(localeIdentifier: locale)
        let userPrompt = PromptBuilder.buildOneLinerUserPrompt(
            partInfo: partInfo,
            fullTranscript: fullTranscript,
            positives: positives,
            observations: observations,
            localeIdentifier: locale
        )

        XCTAssertTrue(systemPrompt.contains("bullet points"))
        XCTAssertTrue(systemPrompt.contains("English"))
        XCTAssertTrue(userPrompt.contains("Test Part"))
        XCTAssertTrue(userPrompt.contains("Point 1"))
        XCTAssertTrue(userPrompt.contains("Good point"))
        XCTAssertTrue(userPrompt.contains("He smiled"))
        XCTAssertTrue(userPrompt.contains("Observed"))
        XCTAssertTrue(userPrompt.contains("He sat down"))
        XCTAssertTrue(userPrompt.contains(fullTranscript))
        XCTAssertTrue(userPrompt.contains("English"))

        // English headers
        XCTAssertTrue(userPrompt.contains("## Current Part Information"))
        XCTAssertTrue(userPrompt.contains("## Analyzed Candidates"))
    }

    func testAnalysisResultParsing() async throws {
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

    func testGenerateOneLinerTimeout() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let keychain = MockKeychainService()
        try keychain.save(key: KeychainKeys.openaiApiKey, value: "test-key")

        // Use a small timeout for testing
        let service = OpenAILLMService(keychainService: keychain, session: session, timeout: 0.1)

        MockURLProtocol.requestHandler = { request in
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000) // Sleep 1s
            throw URLError(.timedOut)
        }

        let partInfo = PartDefinition(
            id: "p1",
            number: 1,
            title: "T1",
            durationMinutes: nil,
            setting: nil,
            rawMarkdown: "",
            learningPoints: [],
            observationItems: [],
            positiveItems: []
        )

        do {
            _ = try await service.generateOneLiner(
                partInfo: partInfo,
                fullTranscript: "",
                positives: [],
                observations: [],
                localeIdentifier: "ja-JP"
            )
            XCTFail("Should have timed out")
        } catch let error as LLMError {
            if case .timeout = error {
                // Success
            } else {
                XCTFail("Expected timeout error, got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError.timeout, got \(error)")
        }
    }
}

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }

        Task {
            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
