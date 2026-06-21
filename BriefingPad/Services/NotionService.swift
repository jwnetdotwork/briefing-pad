import Foundation
import CryptoKit

enum NotionUpdateResult {
    case success(lastEditedTime: String, contentHash: String)
    case externalModification(newBlockId: String, lastEditedTime: String, contentHash: String)
    case failure(String)
}

protocol NotionServiceProtocol {
    func upsertAIMemo(
        blockId: String,
        content: String,
        expectedLastEditedTime: String?,
        expectedContentHash: String?
    ) async throws -> NotionUpdateResult
}

class NotionService: NotionServiceProtocol {
    private let client: NotionClientProtocol

    init(client: NotionClientProtocol) {
        self.client = client
    }

    func upsertAIMemo(
        blockId: String,
        content: String,
        expectedLastEditedTime: String?,
        expectedContentHash: String?
    ) async throws -> NotionUpdateResult {
        do {
            // 1. Fetch current AI Memo header block
            let headerBlock = try await client.fetchBlock(blockId: blockId)
            let parentId = headerBlock.parent?.block_id ?? headerBlock.parent?.page_id
            guard let parentId = parentId else {
                return .failure("Parent ID not found")
            }

            // 2. Conflict Detection
            let currentLastEditedTime = headerBlock.last_edited_time ?? ""

            // We need to fetch the existing frame blocks to calculate the hash of what is currently on Notion
            let allBlocks = try await client.fetchBlocks(blockId: parentId)
            let frame = findFrame(headerId: blockId, allBlocks: allBlocks)
            let existingNotionContent = frame.blocks.map { getPlainText($0) }.joined(separator: "\n")
            let existingNotionHash = calculateHash(content: existingNotionContent)

            let isModifiedExternally: Bool
            if let expectedTime = expectedLastEditedTime, let expectedHash = expectedContentHash {
                // If Notion's last_edited_time is newer than our expected time, AND the hash has changed
                isModifiedExternally = (currentLastEditedTime > expectedTime) && (existingNotionHash != expectedHash)
            } else {
                isModifiedExternally = false
            }

            // 3. Prepare Blocks
            let blocksToAppend = prepareBlocks(content: content)

            if isModifiedExternally {
                // Conflict: Append at the end of the frame
                let newBlocks = try await client.appendBlocks(blockId: parentId, children: blocksToAppend)
                if let newHeader = newBlocks.first {
                    return .externalModification(
                        newBlockId: newHeader.id,
                        lastEditedTime: newHeader.last_edited_time ?? "",
                        contentHash: calculateHash(content: content)
                    )
                }
                return .failure("Failed to append new blocks")
            } else {
                // No conflict: Replace frame content
                // Delete existing blocks in frame (including the old header)
                for block in frame.blocks {
                    try await client.deleteBlock(blockId: block.id)
                }

                // Append new blocks
                let newBlocks = try await client.appendBlocks(blockId: parentId, children: blocksToAppend)

                if let newHeader = newBlocks.first {
                    return .success(
                        lastEditedTime: newHeader.last_edited_time ?? "",
                        contentHash: calculateHash(content: content)
                    )
                }
                return .failure("Failed to append blocks")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func calculateHash(content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func findFrame(headerId: String, allBlocks: [NotionBlock]) -> (header: NotionBlock, blocks: [NotionBlock]) {
        guard let headerIndex = allBlocks.firstIndex(where: { $0.id == headerId }) else {
            // Should not happen if headerId is valid, but fallback to single block
            if let block = allBlocks.first(where: { $0.id == headerId }) {
                return (block, [block])
            }
            return (allBlocks[0], [])
        }

        let header = allBlocks[headerIndex]
        var frameBlocks: [NotionBlock] = [header]

        for i in (headerIndex + 1)..<allBlocks.count {
            let block = allBlocks[i]
            // Frame ends if we hit another header
            if block.type.contains("heading") {
                break
            }
            frameBlocks.append(block)
        }

        return (header, frameBlocks)
    }

    private func prepareBlocks(content: String) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Header
        blocks.append([
            "object": "block",
            "type": "heading_3",
            "heading_3": [
                "rich_text": [
                    ["type": "text", "text": ["content": "🤖AIメモ"]]
                ]
            ]
        ])

        // The content format from formatFinalMemo:
        // ◎ 短評で使えそう
        // - Item: Evidence
        //
        // 👀 根拠になりそうな観察
        // - Item: Evidence
        //
        // 💡 言えそうな一言
        // One liner

        let sections = content.components(separatedBy: "\n\n")
        for section in sections {
            let lines = section.components(separatedBy: "\n").filter { !$0.isEmpty }
            if let firstLine = lines.first {
                blocks.append([
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            ["type": "text", "text": ["content": firstLine]]
                        ]
                    ]
                ])

                for i in 1..<lines.count {
                    let item = lines[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "")
                    blocks.append([
                        "object": "block",
                        "type": "bulleted_list_item",
                        "bulleted_list_item": [
                            "rich_text": [
                                ["type": "text", "text": ["content": item]]
                            ]
                        ]
                    ])
                }
            }
        }

        return blocks
    }

    private func getPlainText(_ block: NotionBlock) -> String {
        let richTexts: [NotionRichText]
        switch block.type {
        case "heading_3": richTexts = block.heading_3?.rich_text ?? []
        case "paragraph": richTexts = block.paragraph?.rich_text ?? []
        case "bulleted_list_item": richTexts = block.bulleted_list_item?.rich_text ?? []
        default: return ""
        }
        return richTexts.map { $0.plain_text }.joined()
    }
}

class MockNotionService: NotionServiceProtocol {
    var shouldSimulateExternalModification = false

    func upsertAIMemo(
        blockId: String,
        content: String,
        expectedLastEditedTime: String?,
        expectedContentHash: String?
    ) async throws -> NotionUpdateResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        let hash = calculateHash(content: content)
        let time = ISO8601DateFormatter().string(from: Date())

        if shouldSimulateExternalModification {
            shouldSimulateExternalModification = false
            return .externalModification(
                newBlockId: "new-block-id-\(UUID().uuidString)",
                lastEditedTime: time,
                contentHash: hash
            )
        }

        return .success(lastEditedTime: time, contentHash: hash)
    }

    private func calculateHash(content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
