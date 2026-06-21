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
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw mapError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(NotionPage.self, from: data)
    }

    func fetchBlocks(blockId: String) async throws -> [NotionBlock] {
        var allBlocks: [NotionBlock] = []
        var cursor: String?

        repeat {
            var components = URLComponents(string: "https://api.notion.com/v1/blocks/\(blockId)/children")!
            var queryItems = [URLQueryItem(name: "page_size", value: "100")]
            if let c = cursor {
                queryItems.append(URLQueryItem(name: "start_cursor", value: c))
            }
            components.queryItems = queryItems

            guard let url = components.url else { throw NotionError.invalidURL }
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw mapError(statusCode: httpResponse.statusCode)
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
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return true
        }
        return false
    }

    private func mapError(statusCode: Int) -> NotionError {
        switch statusCode {
        case 401: return .authenticationFailed
        case 403: return .permissionDenied
        default: return .fetchFailed
        }
    }

    static func normalizePageId(_ input: String) -> String? {
        // Support UUID direct input
        let uuidPattern = "^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$"
        if input.range(of: uuidPattern, options: .regularExpression) != nil {
            return input.replacingOccurrences(of: "-", with: "")
        }

        // Support app.notion.com/p/PAGE_ID
        // Support app.notion.com/PAGE_TITLE-PAGE_ID
        if input.contains("app.notion.com") || input.contains("notion.so") {
            let urlPattern = "([0-9a-fA-F]{32})"
            if let regex = try? NSRegularExpression(pattern: urlPattern),
               let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let range = Range(match.range(at: 1), in: input) {
                return String(input[range])
            }
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
