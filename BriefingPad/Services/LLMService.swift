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

struct SummarizedItem: Codable, Hashable {
    let id: String
    let text: String
    let evidence: String
}

protocol LLMServiceProtocol {
    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) async throws -> AnalysisResult

    /// 箇条書きのコメント用素材を生成する
    func generateOneLiner(
        partInfo: PartDefinition,
        fullTranscript: String,
        positives: [SummarizedItem],
        observations: [SummarizedItem]
    ) async throws -> String
}

class MockLLMService: LLMServiceProtocol {
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 1_000_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) async throws -> AnalysisResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: delayNanoseconds)

        return AnalysisResult(
            observationMatches: partInfo.observationItems.prefix(1).map {
                ItemMatch(itemId: $0.id, confidence: 0.9, shortEvidence: "Mock observation match")
            },
            positiveMatches: partInfo.positiveItems.prefix(1).map {
                ItemMatch(itemId: $0.id, confidence: 0.7, shortEvidence: "Mock positive match")
            }
        )
    }

    func generateOneLiner(
        partInfo: PartDefinition,
        fullTranscript: String,
        positives: [SummarizedItem],
        observations: [SummarizedItem]
    ) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return "素晴らしい対応でした。特に相手の状況を汲み取った発言が印象的です。"
    }
}
