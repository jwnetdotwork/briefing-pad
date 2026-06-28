import Foundation

enum LocalBriefingDataStore {
    static func loadSessions(bundle: Bundle = .main) -> [BriefingSession] {
        guard let url = bundle.url(forResource: "part_definitions", withExtension: "json") else {
            return fallbackSessions
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let createdAt = attributes?[.creationDate] as? Date
        let updatedAt = attributes?[.modificationDate] as? Date

        do {
            let data = try Data(contentsOf: url)
            let currentDecoder = decoder()
            if let createdAt = createdAt {
                currentDecoder.userInfo[.sessionCreatedAt] = createdAt
            }
            if let updatedAt = updatedAt {
                currentDecoder.userInfo[.sessionUpdatedAt] = updatedAt
            }
            let catalog = try currentDecoder.decode(LocalBriefingCatalog.self, from: data)
            return catalog.sessions
        } catch {
            return fallbackSessions
        }
    }

    static var fallbackSessions: [BriefingSession] {
        let date20 = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 20)) ?? Date()
        let date21 = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 21)) ?? Date()
        return [
            BriefingSession(
                id: "2024-06-20-practice",
                name: "2024/06/20 実演練習",
                parts: [
                    PartDefinition(
                        id: "part-1-greeting",
                        number: 1,
                        title: "挨拶をする",
                        durationMinutes: 2,
                        setting: "相手に自然に声をかける導入",
                        rawMarkdown: """
                        ### Part 1. 挨拶をする

                        こんにちは。今日はいい天気ですね。最近はいかがお過ごしですか？
                        """,
                        learningPoints: [
                            LearningPoint(id: "lp-1", text: "笑顔で最初の一言を置く"),
                            LearningPoint(id: "lp-2", text: "相手が返しやすい質問を混ぜる")
                        ],
                        observationItems: [
                            ObservationItem(id: "obs-1", text: "笑顔で挨拶できているか"),
                            ObservationItem(id: "obs-2", text: "相手の反応を待てているか")
                        ],
                        positiveItems: [
                            PositiveItem(id: "pos-1", text: "自然な笑顔で話しかけられていた"),
                            PositiveItem(id: "pos-2", text: "最初の一言が落ち着いていた")
                        ],
                        aiMemo: "冒頭の挨拶はスムーズで、相手の反応を待つ余裕もあった。",
                        aiMemoBlockId: "notion-block-id-1"
                    ),
                    PartDefinition(
                        id: "part-4-conversation",
                        number: 4,
                        title: "会話を始める",
                        durationMinutes: 4,
                        setting: "親切な声かけをきっかけに会話へつなげる",
                        rawMarkdown: """
                        ### Part 4. 会話を始める

                        お手伝いしましょうか？荷物が重そうですね。
                        ありがとうございます。助かります。
                        いいえ、こちらの道はよく通られるんですか？
                        """,
                        learningPoints: [
                            LearningPoint(id: "lp-3", text: "助ける一言から会話を開く"),
                            LearningPoint(id: "lp-4", text: "相手が安心したあとに話題を広げる")
                        ],
                        observationItems: [
                            ObservationItem(id: "obs-3", text: "相手の困り事に気づいて声をかけているか"),
                            ObservationItem(id: "obs-4", text: "助けた後に自然に会話を広げているか"),
                            ObservationItem(id: "obs-5", text: "相手が安心したと感じられる反応があるか")
                        ],
                        positiveItems: [
                            PositiveItem(id: "pos-3", text: "親切をきっかけにしたので構えさせにくい流れ"),
                            PositiveItem(id: "pos-4", text: "助けたい気持ちが先に出て真心が伝わりやすい")
                        ],
                        aiMemo: "親切な行動が会話の起点になり、相手の安心感を崩さずに展開できていた。",
                        aiMemoBlockId: "notion-block-id-4"
                    )
                ],
                createdAt: date20,
                updatedAt: date20
            ),
            BriefingSession(
                id: "2024-06-21-final",
                name: "2024/06/21 本番",
                parts: [
                    PartDefinition(
                        id: "part-1-intro",
                        number: 1,
                        title: "導入",
                        durationMinutes: 3,
                        setting: "開始直後の空気を整える",
                        rawMarkdown: """
                        ### Part 1. 導入

                        ダミーの文字起こしテキストです。
                        """,
                        learningPoints: [
                            LearningPoint(id: "lp-5", text: "相手の様子を見てから入る")
                        ],
                        observationItems: [
                            ObservationItem(id: "obs-6", text: "冒頭で間を取れているか")
                        ],
                        positiveItems: [
                            PositiveItem(id: "pos-5", text: "落ち着いた入り方だった")
                        ],
                        aiMemo: "導入は落ち着いており、次の会話へつなげる下地はできている。",
                        aiMemoBlockId: "notion-block-id-final-1"
                    )
                ],
                createdAt: date21,
                updatedAt: date21
            )
        ]
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
