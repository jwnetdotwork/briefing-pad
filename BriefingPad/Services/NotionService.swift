import Foundation

enum NotionUpdateResult {
    case success
    case externalModification(newBlockId: String)
    case failure(String)
}

protocol NotionServiceProtocol {
    func upsertAIMemo(blockId: String, content: String) async throws -> NotionUpdateResult
}

class MockNotionService: NotionServiceProtocol {
    var shouldSimulateExternalModification = false

    func upsertAIMemo(blockId: String, content: String) async throws -> NotionUpdateResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        if shouldSimulateExternalModification {
            shouldSimulateExternalModification = false
            return .externalModification(newBlockId: "new-block-id-\(UUID().uuidString)")
        }

        return .success
    }
}
