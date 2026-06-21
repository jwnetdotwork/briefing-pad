import Foundation
import Testing
@testable import BriefingPad

struct NotionParserTests {
    @Test func testParseSampleJson() async throws {
        let testBundle = Bundle(for: TestBundleToken.self)
        guard let url = testBundle.url(forResource: "notion_page_sample", withExtension: "json") else {
            Issue.record("notion_page_sample.json not found")
            return
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let blockList = try decoder.decode(NotionBlockList.self, from: data)

        let parser = NotionParser()
        let session = parser.parse(blocks: blockList.results, sessionName: "Test Session")

        // Check filtering
        // Part 1, 2 should be excluded.
        // Part 3, 4, 5 should be included.
        #expect(session.parts.count == 3)

        let part3 = session.parts.first { $0.number == 3 }
        #expect(part3 != nil)
        #expect(part3?.title == "聖書朗読 山田二郎")
        #expect(part3?.durationMinutes == 4)
        #expect(part3?.setting == "エレ 9:13-24")
        // Sample JSON has bullet points for these
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

        let part5 = session.parts.first { $0.number == 5 }
        #expect(part5 != nil)
        #expect(part5?.title == "会話を始める 山田三郎/山田四郎")
        #expect(part5?.durationMinutes == 4)
        #expect(part5?.setting == "家から家で。（LINEで証言を行なうという場面設定）")

        // Verify rawMarkdown contains everything
        #expect(part3?.rawMarkdown.contains("📓学習ポイント") == true)
        #expect(part3?.rawMarkdown.contains("👀観察メモ") == true)
        #expect(part3?.rawMarkdown.contains("👍どこがどのように良かったか") == true)
        #expect(part3?.rawMarkdown.contains("☔次の一歩") == true)

        // Part 4 also has 📓学習ポイント 👀観察メモ 👍どこがどのように良かったか ☔次の一歩
        #expect(part4?.rawMarkdown.contains("📓学習ポイント") == true)
    }
}

private final class TestBundleToken {}
