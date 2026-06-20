import Foundation

struct Part: Identifiable {
    let id = UUID()
    let title: String
    let durationMinutes: Int
    let transcription: String
    let observationPoints: [String]
    let goodPoints: [String]
    let aiMemo: String
}

struct Session: Identifiable {
    let id = UUID()
    var name: String
    var parts: [Part]
}

extension Session {
    static let dummySessions: [Session] = [
        Session(name: "2024/06/20 実演練習", parts: [
            Part(
                title: "Part 1. 挨拶をする",
                durationMinutes: 2,
                transcription: "こんにちは。今日はいい天気ですね。最近はいかがお過ごしですか？",
                observationPoints: [
                    "笑顔で挨拶できているか",
                    "相手の反応を待てているか"
                ],
                goodPoints: [
                    "自然な笑顔で話しかけられていた"
                ],
                aiMemo: "冒頭の挨拶は非常にスムーズでした。"
            ),
            Part(
                title: "Part 4. 会話を始める",
                durationMinutes: 4,
                transcription: "お手伝いしましょうか？荷物が重そうですね。\nありがとうございます。助かります。\nいいえ、こちらの道はよく通られるんですか？",
                observationPoints: [
                    "相手の困り事に気づいて声をかけているか",
                    "実際に差し伸べた助けは適切か",
                    "助けた時のやわらかい一言",
                    "相手が安心したと感じられる反応"
                ],
                goodPoints: [
                    "親切をきっかけにしたので、最初から構えさせにくい流れ",
                    "助けたい気持ちが先に出ると、真心が伝わりやすい"
                ],
                aiMemo: "親切な行動が会話のきっかけになっていた。\n相手を助けたい気持ちが先に出ていて、学習ポイントに合っていた。"
            )
        ]),
        Session(name: "2024/06/21 本番", parts: [
            Part(
                title: "Part 1. 導入",
                durationMinutes: 3,
                transcription: "ダミーの文字起こしテキストです。",
                observationPoints: ["ポイント1"],
                goodPoints: ["良かった点1"],
                aiMemo: "AIメモ1"
            )
        ])
    ]
}
