import Foundation

struct ItemMatch: Codable, Hashable {
    let itemId: String
    let confidence: Double
    let shortEvidence: String // Or shortReason
}

struct AnalysisResult: Codable, Hashable {
    let observationMatches: [ItemMatch]
    let positiveMatches: [ItemMatch]
}

protocol LLMServiceProtocol {
    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) async throws -> AnalysisResult
}

class MockLLMService: LLMServiceProtocol {
    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) async throws -> AnalysisResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        return AnalysisResult(
            observationMatches: partInfo.observationItems.prefix(1).map {
                ItemMatch(itemId: $0.id, confidence: 0.9, shortEvidence: "Mock observation match")
            },
            positiveMatches: partInfo.positiveItems.prefix(1).map {
                ItemMatch(itemId: $0.id, confidence: 0.7, shortEvidence: "Mock positive match")
            }
        )
    }
}
