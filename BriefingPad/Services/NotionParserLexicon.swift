import Foundation

enum ChapterType: String, CaseIterable {
    case treasureOfGodsWord
    case fieldMinistry
}

struct NotionParserLexicon {
    static func chapterType(for text: String) -> ChapterType? {
        let normalized = normalize(text)
        for type in ChapterType.allCases {
            if aliases(for: type).contains(where: { normalize($0) == normalized }) {
                return type
            }
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func aliases(for type: ChapterType) -> [String] {
        switch type {
        case .treasureOfGodsWord:
            return [
                "神の言葉の宝",
                "TREASURES FROM GOD’S WORD",
                "上帝话语的宝藏",
                "上帝話語的寶藏",
                "पाएँ बाइबल का खज़ाना",
                "TESOROS DE LA BIBLIA",
                "JOYAUX DE LA PAROLE DE DIEU",
                "TESOUROS DA PALAVRA DE DEUS",
                "СОКРОВИЩА ИЗ СЛОВА БОГА"
            ]
        case .fieldMinistry:
            return [
                "野外奉仕に励む",
                "APPLY YOURSELF TO THE FIELD MINISTRY",
                "用心准备传道工作",
                "用心準備傳道工作",
                "बढ़ाएँ प्रचार करने का हुनर",
                "SEAMOS MEJORES MAESTROS",
                "APPLIQUE-TOI AU MINISTÈRE",
                "EMPENHE-SE NO MINISTÉRIO",
                "ОТТАЧИВАЕМ НАВЫКИ СЛУЖЕНИЯ"
            ]
        }
    }
}
