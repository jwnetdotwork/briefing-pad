import Foundation

class NotionParser {
    enum Label: String, CaseIterable {
        case learningPoints = "📓"
        case observationItems = "👀"
        case positiveItems = "👍"
        case aiMemo = "🤖"
        case nextStep = "☔"
        case summary = "👪"
        case preInfo = "事前情報"

        var isStructured: Bool {
            switch self {
            case .learningPoints, .observationItems, .positiveItems, .aiMemo:
                return true
            default:
                return false
            }
        }
    }

    func parse(blocks: [NotionBlock], sessionName: String) -> BriefingSession {
        var parts: [PartDefinition] = []
        var currentChapter: String?
        var currentPartBlocks: [NotionBlock] = []
        var currentPartHeader: (id: String, text: String)?

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
                currentChapter = text
                continue
            }

            if block.type == "heading_3", text.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                flushPart()
                currentPartHeader = (block.id, text)
                currentPartBlocks = [block]
                continue
            }

            if currentPartHeader != nil {
                currentPartBlocks.append(block)
            }
        }
        flushPart()

        return BriefingSession(
            id: UUID().uuidString,
            name: sessionName,
            parts: parts
        )
    }

    private func processPart(blocks: [NotionBlock], headerId: String, headerText: String, chapter: String) -> PartDefinition? {
        // Filter chapters
        guard ["神の言葉の宝", "野外奉仕に励む"].contains(chapter) else { return nil }

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
        if chapter == "神の言葉の宝" {
            if number != 3 { return nil }
        } else if chapter == "野外奉仕に励む" {
            // Keep all numbered parts (usually 4, 5)
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

            // Label detection
            var detectedLabel: Label?
            for label in Label.allCases {
                if text.contains(label.rawValue) {
                    detectedLabel = label
                    break
                }
            }

            if let label = detectedLabel {
                labelEncountered = true
                if label.isStructured {
                    currentLabel = label
                } else {
                    currentLabel = nil
                }

                if label == .aiMemo {
                    aiMemoBlockId = block.id
                }

                if label.isStructured {
                    let labelRaw = label.rawValue
                    if let labelRange = text.range(of: labelRaw) {
                        let content = text.replacingCharacters(in: labelRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                        if !isIgnorableHeader(content, for: label) && !content.isEmpty {
                            addContent(content, to: label, learningPoints: &learningPoints, observationItems: &observationItems, positiveItems: &positiveItems, aiMemo: &aiMemo)
                        }
                    }
                }
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

    private func isIgnorableHeader(_ content: String, for label: Label) -> Bool {
        switch label {
        case .learningPoints: return content == "学習ポイント"
        case .observationItems: return content == "観察メモ"
        case .positiveItems: return content == "どこがどのように良かったか"
        case .aiMemo: return content == "AIメモ"
        default: return false
        }
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
