import Foundation

struct NotionPreview {
    let sessionName: String
    let pageId: String
    let parts: [PartPreview]
    let uninterpretedBlockCount: Int

    struct PartPreview {
        let title: String
        let durationMinutes: Int?
        let setting: String?
        let learningPointCount: Int
        let observationItemCount: Int
        let positiveItemCount: Int
        let hasAIMemo: Bool
    }
}

protocol NotionImportServiceProtocol {
    func testConnection(token: String, pageId: String) async throws
    func generatePreview(token: String, pageId: String) async throws -> NotionPreview
    func importSession(token: String, pageId: String) async throws -> BriefingSession
}

class NotionImportService: NotionImportServiceProtocol {
    private let parser: NotionParser

    init(parser: NotionParser = NotionParser()) {
        self.parser = parser
    }

    func testConnection(token: String, pageId: String) async throws {
        let client = NotionClient(token: token)
        let isConnected = try await client.testConnection()
        if !isConnected {
            throw NotionError.authenticationFailed
        }

        do {
            _ = try await client.fetchPage(pageId: pageId)
        } catch {
            throw NotionError.permissionDenied
        }
    }

    func generatePreview(token: String, pageId: String) async throws -> NotionPreview {
        let client = NotionClient(token: token)
        let page = try await client.fetchPage(pageId: pageId)
        let blocks = try await client.fetchBlocksRecursively(blockId: pageId)

        let result = parser.parse(blocks: blocks, sessionName: page.title)

        let partPreviews = result.session.parts.map { part in
            NotionPreview.PartPreview(
                title: part.title,
                durationMinutes: part.durationMinutes,
                setting: part.setting,
                learningPointCount: part.learningPoints.count,
                observationItemCount: part.observationItems.count,
                positiveItemCount: part.positiveItems.count,
                hasAIMemo: !part.aiMemo.isEmpty || part.aiMemoBlockId != nil
            )
        }

        return NotionPreview(
            sessionName: page.title,
            pageId: pageId,
            parts: partPreviews,
            uninterpretedBlockCount: result.uninterpretedBlockCount
        )
    }

    func importSession(token: String, pageId: String) async throws -> BriefingSession {
        let client = NotionClient(token: token)
        let page = try await client.fetchPage(pageId: pageId)
        let blocks = try await client.fetchBlocksRecursively(blockId: pageId)

        let result = parser.parse(blocks: blocks, sessionName: page.title)
        return result.session
    }
}
