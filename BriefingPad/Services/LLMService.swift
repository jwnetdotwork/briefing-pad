import Foundation

protocol LLMServiceProtocol {
    func updateAIMemo(
        existingMemo: String,
        newTranscriptChunk: String,
        partInfo: PartDefinition
    ) async throws -> String
}

class MockLLMService: LLMServiceProtocol {
    func updateAIMemo(
        existingMemo: String,
        newTranscriptChunk: String,
        partInfo: PartDefinition
    ) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        return """
        ◎ 短評で使えそう
        - 親切な行動が会話のきっかけになっていた。
        - 相手を助けたい気持ちが先に出ていて、学習ポイントに合っていた。

        👀 根拠になりそうな観察
        - 「お手伝いしましょうか」と声をかけていた。
        - \(newTranscriptChunk)

        💡 言えそうな一言
        親切な行動が先にあったので、相手も構えずに会話に入りやすかったと思います。
        """
    }
}
