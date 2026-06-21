import Foundation

protocol NotionClientProtocol {
    func fetchPage(pageId: String) async throws -> NotionPage
    func fetchBlocks(blockId: String) async throws -> [NotionBlock]
    func fetchBlocksRecursively(blockId: String) async throws -> [NotionBlock]
    func testConnection() async throws -> Bool
}

class NotionClient: NotionClientProtocol {
    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchPage(pageId: String) async throws -> NotionPage {
        let url = URL(string: "https://api.notion.com/v1/pages/\(pageId)")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NotionError.fetchFailed
        }

        return try decoder.decode(NotionPage.self, from: data)
    }

    func fetchBlocks(blockId: String) async throws -> [NotionBlock] {
        var allBlocks: [NotionBlock] = []
        var cursor: String?

        repeat {
            var urlString = "https://api.notion.com/v1/blocks/\(blockId)/children?page_size=100"
            if let c = cursor {
                urlString += "&start_cursor=\(c)"
            }
            let url = URL(string: urlString)!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw NotionError.fetchFailed
            }

            let list = try decoder.decode(NotionBlockList.self, from: data)
            allBlocks.append(contentsOf: list.results)
            cursor = list.has_more ? list.next_cursor : nil
        } while cursor != nil

        return allBlocks
    }

    func fetchBlocksRecursively(blockId: String) async throws -> [NotionBlock] {
        let topBlocks = try await fetchBlocks(blockId: blockId)
        var resultBlocks: [NotionBlock] = []

        for block in topBlocks {
            resultBlocks.append(block)
            if block.has_children {
                let childBlocks = try await fetchBlocksRecursively(blockId: block.id)
                resultBlocks.append(contentsOf: childBlocks)
            }
        }

        return resultBlocks
    }

    func testConnection() async throws -> Bool {
        let url = URL(string: "https://api.notion.com/v1/users/me")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }
        return true
    }

    static func normalizePageId(_ input: String) -> String? {
        // Support UUID direct input
        let uuidPattern = "^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$"
        if input.range(of: uuidPattern, options: .regularExpression) != nil {
            return input.replacingOccurrences(of: "-", with: "")
        }

        // Support app.notion.com/p/PAGE_ID
        // Support app.notion.com/PAGE_TITLE-PAGE_ID
        let urlPattern = "([0-9a-fA-F]{32})"
        if let regex = try? NSRegularExpression(pattern: urlPattern),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
           let range = Range(match.range(at: 1), in: input) {
            return String(input[range])
        }

        return nil
    }
}

enum NotionError: Error {
    case invalidURL
    case fetchFailed
    case authenticationFailed
    case permissionDenied
}
