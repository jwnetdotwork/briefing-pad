import Foundation
import Testing
@testable import BriefingPad

struct LocalizationAndParserTests {

    @Test func testNotionContentLocalization() {
        let positives = [SummarizedItem(id: "p1", text: "Positive 1", evidence: " (Good job)")]
        let observations = [SummarizedItem(id: "o1", text: "Observation 1", evidence: " (I saw this)")]
        let aiMemo = "AI recommendation"

        // We can't easily change the system locale in unit tests, but we can check if it uses NSLocalizedString
        // To be more deterministic, we can check for specific substrings that should be there.
        let content = SessionViewModel.assembleNotionContent(
            positives: positives,
            observations: observations,
            aiMemo: aiMemo
        )

        // Check if content includes items
        #expect(content.contains("Positive 1"))
        #expect(content.contains("(Good job)"))
        #expect(content.contains("Observation 1"))
        #expect(content.contains("(I saw this)"))
        #expect(content.contains("AI recommendation"))

        // Check if it has three sections (split by \n\n)
        let sections = content.components(separatedBy: "\n\n")
        #expect(sections.count == 3)
    }

    @Test func testNotionPageTitleFallback() {
        let page = NotionPage(id: "test", properties: [:])
        #expect(page.title == NSLocalizedString("notion.page.untitled", comment: ""))
    }

    @Test func testDurationParsingVariations() {
        let parser = NotionParser()

        let cases = [
            ("（5分）", 5),
            ("(5 min)", 5),
            ("(5 mins)", 5),
            ("(5m)", 5),
            ("（3分钟）", 3),
            ("(10)", 10),
            ("No duration here", nil),
            ("(invalid)", nil)
        ]

        for (text, expectedMinutes) in cases {
            let blocks = [
                createHeading2Block(text: "TREASURES FROM GOD’S WORD"),
                createHeading3Block(text: "3. Title"),
                createParagraphBlock(text: text)
            ]
            let result = parser.parse(blocks: blocks, sessionName: "Test")
            #expect(result.session.parts.count == 1)
            #expect(result.session.parts[0].durationMinutes == expectedMinutes, "Failed for text: \(text)")
        }
    }

    // Helper functions (copied from NotionParserTests.swift)
    private func createHeading2Block(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "heading_2", has_children: false, last_edited_time: nil, parent: nil, heading_2: NotionHeading(rich_text: [NotionRichText(plain_text: text)], is_toggleable: false), heading_3: nil, heading_4: nil, paragraph: nil, bulleted_list_item: nil, image: nil, toggle: nil)
    }

    private func createHeading3Block(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "heading_3", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: NotionHeading(rich_text: [NotionRichText(plain_text: text)], is_toggleable: false), heading_4: nil, paragraph: nil, bulleted_list_item: nil, image: nil, toggle: nil)
    }

    private func createParagraphBlock(text: String) -> NotionBlock {
        return NotionBlock(id: UUID().uuidString, type: "paragraph", has_children: false, last_edited_time: nil, parent: nil, heading_2: nil, heading_3: nil, heading_4: nil, paragraph: NotionTextContent(rich_text: [NotionRichText(plain_text: text)]), bulleted_list_item: nil, image: nil, toggle: nil)
    }
}
