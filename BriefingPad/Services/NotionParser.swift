import Foundation

class NotionParser {
    enum Label: String, CaseIterable {
        case learningPoints = "📓"
        case observationItems = "👀"
        case positiveItems = "👍"
        case aiMemo = "🤖"
        case nextStep = "☔"
        case summary = "👪"

        var isStructured: Bool {
            switch self {
            case .learningPoints, .observationItems, .positiveItems, .aiMemo:
                return true
            default:
                return false
            }
        }
    }

    struct ParseResult {
        let session: BriefingSession
        let uninterpretedBlockCount: Int
    }

    func parse(blocks: [NotionBlock], sessionName: String) -> ParseResult {
        var parts: [PartDefinition] = []
        var currentChapter: ChapterType?
        var currentPartBlocks: [NotionBlock] = []
        var currentPartHeader: (id: String, text: String)?
        var uninterpretedBlockCount = 0

        func flushPart() {
            guard let header = currentPartHeader, let chapter = currentChapter else { return }
            if let part = processPart(blocks: currentPartBlocks, headerId: header.id, headerText: header.text, chapter: chapter) {
                parts.append(part)
            }
            currentPartBlocks = []
            currentPartHeader = nil
        }

        for block in blocks {
            let text = getPlainText(block)

            if block.type == "heading_2" {
                flushPart()
                currentChapter = NotionParserLexicon.chapterType(for: text)
                if currentChapter == nil {
                    uninterpretedBlockCount += 1
                }
                continue
            }

            if block.type == "heading_3", text.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                flushPart()
                currentPartHeader = (block.id, text)
                currentPartBlocks = [block]

                if currentChapter == nil {
                    uninterpretedBlockCount += 1
                }
                continue
            }

            if currentPartHeader != nil {
                currentPartBlocks.append(block)
                if currentChapter == nil {
                    uninterpretedBlockCount += 1
                }
            } else {
                // Blocks outside any part
                if currentChapter == nil {
                    // Blocks before any chapter or in uninterpreted chapter
                    uninterpretedBlockCount += 1
                }
            }
        }
        flushPart()

        let now = Date()
        let session = BriefingSession(
            id: UUID().uuidString,
            name: sessionName,
            parts: parts,
            createdAt: now,
            updatedAt: now
        )
        return ParseResult(session: session, uninterpretedBlockCount: uninterpretedBlockCount)
    }

    private func processPart(blocks: [NotionBlock], headerId: String, headerText: String, chapter: ChapterType) -> PartDefinition? {
        // Parse header for number and title
        let pattern = #"^(\d+)\.\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: headerText, range: NSRange(headerText.startIndex..., in: headerText)) else {
            return nil
        }

        guard let numberRange = Range(match.range(at: 1), in: headerText),
              let titleRange = Range(match.range(at: 2), in: headerText),
              let number = Int(headerText[numberRange]) else {
            return nil
        }

        let title = String(headerText[titleRange])

        // Filter parts
        switch chapter {
        case .treasureOfGodsWord:
            if number != 3 { return nil }
        case .fieldMinistry:
            break // Keep all numbered parts (usually 4, 5)
        }

        var durationMinutes: Int?
        var setting: String?
        var learningPoints: [LearningPoint] = []
        var observationItems: [ObservationItem] = []
        var positiveItems: [PositiveItem] = []
        var aiMemo = ""
        var aiMemoBlockId: String?
        var rawMarkdown = ""

        var currentLabel: Label?
        var durationFound = false
        var labelEncountered = false

        for block in blocks {
            var text = getPlainText(block).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && block.type != "image" { continue }

            rawMarkdown += (rawMarkdown.isEmpty ? "" : "\n") + text

            // Duration check
            if !durationFound, let dMatch = text.range(of: #"（(\d+)分）"#, options: .regularExpression) {
                if let dRange = text.range(of: #"\d+"#, options: .regularExpression, range: dMatch) {
                    durationMinutes = Int(text[dRange])
                }
                durationFound = true

                text = text.replacingCharacters(in: dMatch, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
            }

            // Label detection (must start with the emoji)
            var detectedLabel: Label?
            for label in Label.allCases {
                if text.hasPrefix(label.rawValue) {
                    detectedLabel = label
                    break
                }
            }

            if let label = detectedLabel {
                labelEncountered = true
                currentLabel = label.isStructured ? label : nil

                if label == .aiMemo {
                    aiMemoBlockId = block.id
                }

                // Requirement: Ignore any other text on the same line as the emoji.
                continue
            }

            // Content extraction
            if let label = currentLabel {
                addContent(text, to: label, learningPoints: &learningPoints, observationItems: &observationItems, positiveItems: &positiveItems, aiMemo: &aiMemo)
            } else if durationFound && !labelEncountered {
                // Setting is the first meaningful text after duration before any label
                if setting == nil {
                    setting = text
                }
            }
        }

        return PartDefinition(
            id: headerId,
            number: number,
            title: title,
            durationMinutes: durationMinutes,
            setting: setting,
            rawMarkdown: rawMarkdown,
            learningPoints: learningPoints,
            observationItems: observationItems,
            positiveItems: positiveItems,
            aiMemo: aiMemo,
            aiMemoBlockId: aiMemoBlockId
        )
    }

    private func addContent(_ text: String, to label: Label, learningPoints: inout [LearningPoint], observationItems: inout [ObservationItem], positiveItems: inout [PositiveItem], aiMemo: inout String) {
        switch label {
        case .learningPoints:
            learningPoints.append(LearningPoint(id: UUID().uuidString, text: text))
        case .observationItems:
            observationItems.append(ObservationItem(id: UUID().uuidString, text: text))
        case .positiveItems:
            positiveItems.append(PositiveItem(id: UUID().uuidString, text: text))
        case .aiMemo:
            if aiMemo.isEmpty {
                aiMemo = text
            } else {
                aiMemo += "\n" + text
            }
        default:
            break
        }
    }

    private func getPlainText(_ block: NotionBlock) -> String {
        let richTexts: [NotionRichText]
        switch block.type {
        case "heading_2": richTexts = block.heading_2?.rich_text ?? []
        case "heading_3": richTexts = block.heading_3?.rich_text ?? []
        case "heading_4": richTexts = block.heading_4?.rich_text ?? []
        case "paragraph": richTexts = block.paragraph?.rich_text ?? []
        case "bulleted_list_item": richTexts = block.bulleted_list_item?.rich_text ?? []
        default: return ""
        }
        return richTexts.map { $0.plain_text }.joined()
    }
}
