import Foundation
import Testing
@testable import BriefingPad

struct NotionParserTests {
    @Test func testParseSampleJson() async throws {
        // Use #filePath to find docs relative to this test file
        let currentFile = URL(fileURLWithPath: #filePath)
        let projectRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("docs/notion_page_sample.json")

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let blockList = try decoder.decode(NotionBlockList.self, from: data)

        let parser = NotionParser()
        let result = parser.parse(blocks: blockList.results, sessionName: "Test Session")
        let session = result.session

        // Check filtering
        // Part 1, 2 should be excluded (number 1, 2 in '神の言葉の宝').
        // Part 3 (in '神の言葉の宝'), 4, 5 (in '野外奉仕に励む') should be included.
        #expect(session.parts.count == 3)

        let part3 = session.parts.first { $0.number == 3 }
        #expect(part3 != nil)
        #expect(part3?.title == "聖書朗読 山田二郎")
        #expect(part3?.durationMinutes == 4)
        #expect(part3?.setting == "エレ 9:13-24")
        #expect(part3!.learningPoints.count == 2)
        #expect(part3!.observationItems.count == 5)
        #expect(part3!.positiveItems.count == 4)

        let part4 = session.parts.first { $0.number == 4 }
        #expect(part4 != nil)
        #expect(part4?.title == "会話を始める 山田花子/山田花枝")
        #expect(part4?.durationMinutes == 4)
        #expect(part4?.setting == "日常生活で。")
        #expect(part4!.learningPoints.count == 2)
        #expect(part4!.observationItems.count == 7)
        #expect(part4!.positiveItems.count == 4)

        // Verify uninterpretedBlockCount
        // The sample has blocks before '神の言葉の宝' (6月22-28日..., 5番の歌..., 開会の言葉...)
        // Those should be counted.
        #expect(result.uninterpretedBlockCount > 0)
    }

    @Test func testMultilingualChapterRecognition() {
        let parser = NotionParser()

        let languages = [
            ("TREASURES FROM GOD’S WORD", ChapterType.treasureOfGodsWord),
            ("APPLY YOURSELF TO THE FIELD MINISTRY", ChapterType.fieldMinistry),
            ("TESOROS DE LA BIBLIA", ChapterType.treasureOfGodsWord),
            ("SEAMOS MEJORES MAESTROS", ChapterType.fieldMinistry),
            ("СОКРОВИЩА ИЗ СЛОВА БОГА", ChapterType.treasureOfGodsWord),
            ("ОТТАЧИВАЕМ НАВЫКИ СЛУЖЕНИЯ", ChapterType.fieldMinistry),
            ("上帝话语的宝藏", ChapterType.treasureOfGodsWord),
            ("用心准备传道工作", ChapterType.fieldMinistry)
        ]

        for (name, expectedType) in languages {
            // Assert lexicon directly
            #expect(NotionParserLexicon.chapterType(for: name) == expectedType)

            // Test parser integration
            let blocks = [
                createHeading2Block(text: name),
                createHeading3Block(text: "3. Title"),
                createParagraphBlock(text: "（5分）")
            ]
            let parseResult = parser.parse(blocks: blocks, sessionName: "Test")

            if expectedType == .treasureOfGodsWord {
                #expect(parseResult.session.parts.count == 1, "Failed to recognize \(name) as treasureOfGodsWord")
            } else {
                #expect(parseResult.session.parts.count == 1, "Failed to recognize \(name) as fieldMinistry")
            }
        }

        // Verify Unicode normalization (Decomposed form NFD)
        let nfdTreasure = "神の言葉の宝".applyingTransform(.init("Any-NFD"), reverse: false)!
        #expect(NotionParserLexicon.chapterType(for: nfdTreasure) == .treasureOfGodsWord)
    }

    @Test func testEmojiLabelExtraction() {
        let parser = NotionParser()
        let blocks = [
            createHeading2Block(text: "TREASURES FROM GOD’S WORD"),
            createHeading3Block(text: "3. Title"),
            createParagraphBlock(text: "（5分） Setting"),
            createParagraphBlock(text: "📓Learning Points should be ignored"),
            createBulletBlock(text: "Point 1"),
            createParagraphBlock(text: "This paragraph contains an emoji 👀 in the middle"),
            createBulletBlock(text: "Point 2"),
            createParagraphBlock(text: "👀Observation"),
            createBulletBlock(text: "Obs 1"),
            createParagraphBlock(text: "👍Positive"),
            createBulletBlock(text: "Pos 1"),
            createParagraphBlock(text: "🤖AI Memo"),
            createParagraphBlock(text: "AI content line 1"),
            createParagraphBlock(text: "AI content line 2")
        ]

        let result = parser.parse(blocks: blocks, sessionName: "Test")
        #expect(result.session.parts.count == 1)
        let part = result.session.parts[0]

        // "This paragraph contains an emoji 👀 in the middle" should be part of Learning Points
        #expect(part.learningPoints.count == 3)
        #expect(part.learningPoints[0].text == "Point 1")
        #expect(part.learningPoints[1].text == "This paragraph contains an emoji 👀 in the middle")
        #expect(part.learningPoints[2].text == "Point 2")

        #expect(part.observationItems.count == 1)
        #expect(part.observationItems[0].text == "Obs 1")

        #expect(part.positiveItems.count == 1)
        #expect(part.positiveItems[0].text == "Pos 1")

        #expect(part.aiMemo == "AI content line 1\nAI content line 2")
    }

    @Test func testUninterpretedBlockCount() {
        let parser = NotionParser()
        let blocks = [
            createParagraphBlock(text: "Pre-session info"), // 1
            createHeading2Block(text: "Unknown Chapter"), // 2
            createHeading3Block(text: "1. Part in unknown"), // 3
            createParagraphBlock(text: "Some content"), // 4
            createHeading2Block(text: "神の言葉の宝"),
            createHeading3Block(text: "3. Target Part"),
            createParagraphBlock(text: "Target content"),
            createHeading2Block(text: "Another Unknown"), // 5
            createParagraphBlock(text: "Trailing info") // 6
        ]

        let result = parser.parse(blocks: blocks, sessionName: "Test")
        #expect(result.uninterpretedBlockCount == 6)
        #expect(result.session.parts.count == 1)
    }

    @Test func testNormalizePageId() {
        #expect(NotionClient.normalizePageId("344f63ef-3462-808f-842a-f49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("https://app.notion.com/My-Session-344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("https://app.notion.com/p/344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("invalid") == nil)
    }

    // Helper functions to create blocks for testing
    private func createHeading2Block(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "heading_2", has_children: false, last_edited_time: nil, parent: nil, heading_2: NotionHeading(rich_text: [NotionRichText(plain_text: text)], is_toggleable: false), heading_3: nil, heading_4: nil, paragraph: nil, bulleted_list_item: nil, image: nil, toggle: nil)
    }

    private func createHeading3Block(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "heading_3", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: NotionHeading(rich_text: [NotionRichText(plain_text: text)], is_toggleable: false), heading_4: nil, paragraph: nil, bulleted_list_item: nil, image: nil, toggle: nil)
    }

    private func createParagraphBlock(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "paragraph", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: nil, heading_4: nil, paragraph: NotionTextContent(rich_text: [NotionRichText(plain_text: text)]), bulleted_list_item: nil, image: nil, toggle: nil)
    }

    private func createBulletBlock(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "bulleted_list_item", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: nil, heading_4: nil, paragraph: nil, bulleted_list_item: NotionTextContent(rich_text: [NotionRichText(plain_text: text)]), image: nil, toggle: nil)
    }
}
