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

    @Test func testNormalizePageId() {
        #expect(NotionClient.normalizePageId("344f63ef-3462-808f-842a-f49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("https://app.notion.com/My-Session-344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("https://app.notion.com/p/344f63ef3462808f842af49cbf6bbfd3") == "344f63ef3462808f842af49cbf6bbfd3")
        #expect(NotionClient.normalizePageId("invalid") == nil)
    }
}
