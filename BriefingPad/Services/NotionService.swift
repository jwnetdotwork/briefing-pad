import Foundation
import CryptoKit

enum NotionUpdateResult {
    case success(lastEditedTime: String, contentHash: String)
    case externalModification(newBlockId: String, lastEditedTime: String, contentHash: String)
    case failure(String)
    case noToken
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
    
    private func debugLog(_ event: String, extra: String? = nil) {
        #if DEBUG

        var message = "[NotionService] \(event)"
        if let extra = extra {
            message += " | \(extra)"
        }
        print(message)
        #endif
    }

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
            debugLog("[NotionSync] fetchBlock start - blockId: \(blockId)")
            var headerBlock = try await client.fetchBlock(blockId: blockId)
            let parentId = headerBlock.parent?.block_id ?? headerBlock.parent?.page_id
            guard let parentId = parentId else {
                return .failure("Parent ID not found")
            }

            // 2. Conflict Detection & Normalization
            let currentLastEditedTime = headerBlock.last_edited_time ?? ""
            let isToggle = (headerBlock.heading_3?.is_toggleable ?? false) || (headerBlock.toggle != nil)

            var existingNotionContent = ""
            var blocksToDelete: [String] = []

            if isToggle {
                // Fetch children if it's already a toggle
                let children = try await client.fetchBlocks(blockId: blockId)
                existingNotionContent = children.map { getPlainText($0) }.joined(separator: "\n")
                blocksToDelete = children.map { $0.id }
            } else {
                let children = try await client.fetchBlocks(blockId: blockId)
                existingNotionContent = children.map { getPlainText($0) }.joined(separator: "\n")
                blocksToDelete = children.map { $0.id }
                // Migration: Fetch siblings to find the old-style frame
//                debugLog("[NotionSync] fetchBlock notoggle - blockId: \(parentId)")
//                let allBlocks = try await client.fetchBlocks(blockId: parentId)
//                let frame = findFrame(headerId: blockId, allBlocks: allBlocks)
                // In old style, the header was part of the frame and gets replaced/moved.
                // But we want to KEEP the header and just convert it.
                // Frame includes the header itself as the first element.
//                existingNotionContent = frame.blocks.dropFirst().map { getPlainText($0) }.joined(separator: "\n")
//                blocksToDelete = frame.blocks.dropFirst().map { $0.id }

                // Convert header to toggle
                // We must include the existing rich_text to avoid losing it
//                let existingRichText = headerBlock.paragraph?.rich_text.map { rt in
//                    ["type": "text", "text": ["content": rt.plain_text]]
//                } ?? []
//                
//                debugLog("[NotionSync] fetchBlock update - blockId: \(blockId)")
//                headerBlock = try await client.updateBlock(blockId: blockId, content: [
//                    "paragraph": [
//                        "rich_text": existingRichText
//                    ]
//                ])
            }

            let existingNotionHash = CryptoUtils.calculateHash(content: normalizeContent(existingNotionContent))
            let currentContentHash = CryptoUtils.calculateHash(content: normalizeContent(content))

            let isModifiedExternally: Bool
            if let expectedTime = expectedLastEditedTime, let expectedHash = expectedContentHash {
                let formatter = ISO8601DateFormatter()
                if let currentDate = formatter.date(from: currentLastEditedTime),
                   let expectedDate = formatter.date(from: expectedTime) {
                    isModifiedExternally = (currentDate > expectedDate) && (existingNotionHash != expectedHash)
                } else {
                    isModifiedExternally = (currentLastEditedTime > expectedTime) && (existingNotionHash != expectedHash)
                }
            } else {
                isModifiedExternally = false
            }

            // 3. Update Content
            // Delete old content blocks
            for id in blocksToDelete {
                try await client.deleteBlock(blockId: id)
            }

            // Prepare content (excluding the header which we already have)
            let contentBlocks = prepareContentBlocks(content: content)

            // Append as children of the header toggle
            let newBlocks = try await client.appendBlocks(blockId: blockId, children: contentBlocks)

            // Note: User requested to always overwrite even if conflict.
            // We just return externalModification if we detected one, but we already performed the overwrite.
            if isModifiedExternally {
                return .externalModification(
                    newBlockId: blockId, // blockId doesn't change anymore!
                    lastEditedTime: headerBlock.last_edited_time ?? "",
                    contentHash: currentContentHash
                )
            } else {
                return .success(
                    lastEditedTime: headerBlock.last_edited_time ?? "",
                    contentHash: currentContentHash
                )
            }
        } catch {
            // error の型と中身を両方出力
            debugLog("[NotionSync] ERROR type: \(type(of: error))")
            debugLog("[NotionSync] ERROR dump: \(error)")
            debugLog("[NotionSync] ERROR localized: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    private func findFrame(headerId: String, allBlocks: [NotionBlock]) -> (header: NotionBlock, blocks: [NotionBlock]) {
        guard let headerIndex = allBlocks.firstIndex(where: { $0.id == headerId }) else {
            // Should not happen if headerId is valid, but fallback to single block
            if let block = allBlocks.first(where: { $0.id == headerId }) {
                return (block, [block])
            }
            guard !allBlocks.isEmpty else {
                // Return a dummy block if allBlocks is empty to avoid crash
                let dummy = NotionBlock(id: headerId, type: "unsupported", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: nil, heading_4: nil, paragraph: nil, bulleted_list_item: nil, image: nil)
                return (dummy, [])
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

    private func prepareContentBlocks(content: String) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

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
                    var item = lines[i].trimmingCharacters(in: .whitespaces)
                    if item.hasPrefix("- ") {
                        item = String(item.dropFirst(2))
                    }
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

    private func normalizeContent(_ content: String) -> String {
        return content.components(separatedBy: .newlines)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("- ") {
                    l = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                return l
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
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

        let hash = CryptoUtils.calculateHash(content: content)
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
}

class DisabledNotionService: NotionServiceProtocol {
    func upsertAIMemo(
        blockId: String,
        content: String,
        expectedLastEditedTime: String?,
        expectedContentHash: String?
    ) async throws -> NotionUpdateResult {
        return .noToken
    }
}
