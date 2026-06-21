import Foundation

struct PromptBuilder {
    static func buildSystemPrompt() -> String {
        return """
        あなたは接客やコミュニケーションのトレーニングを支援するAIアシスタントです。
        提供された文字起こしデータ（全文および最新の追加分）を分析し、特定の「観察メモ」および「良かった点候補」に該当する箇所があるかを判定してください。

        以下の制約を厳守してJSON形式で回答してください：
        1. 指定された itemId 以外は返さないこと。
        2. 各項目について、確信度（confidence: 0.0〜1.0）と、その根拠となる短い証拠（shortEvidence）を抽出すること。
        3. 以前は検出されていたが最新の文脈で「もう検出されない/否定された」と判断した場合は、confidence を低く（0.0など）設定すること。
        4. JSONフォーマットは以下の通りとすること：
        {
          "observationMatches": [
            { "itemId": "obs-1", "confidence": 0.9, "shortEvidence": "証拠文言" }
          ],
          "positiveMatches": [
            { "itemId": "pos-1", "confidence": 0.7, "shortEvidence": "証拠文言" }
          ]
        }
        5. 余計な説明や、Markdownのコードブロック（```json ... ```）は含めず、純粋なJSONのみを出力すること。
        """
    }

    static func buildUserPrompt(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) -> String {
        var prompt = "## 現在のパート情報\n"
        prompt += "タイトル: \(partInfo.title)\n"
        if let setting = partInfo.setting {
            prompt += "設定: \(setting)\n"
        }

        prompt += "\n## 学習ポイント\n"
        for lp in partInfo.learningPoints {
            prompt += "- \(lp.text)\n"
        }

        prompt += "\n## 判定対象：観察メモ (observationItems)\n"
        for item in partInfo.observationItems {
            prompt += "- id: \(item.id), 内容: \(item.text)\n"
        }

        prompt += "\n## 判定対象：良かった点候補 (positiveItems)\n"
        for item in partInfo.positiveItems {
            prompt += "- id: \(item.id), 内容: \(item.text)\n"
        }

        prompt += "\n## 現在までの文字起こし全文\n"
        prompt += fullTranscript + "\n"

        prompt += "\n## 最新の追加文字起こし（今回の分析対象）\n"
        prompt += newChunk + "\n"

        prompt += "\n## 回答\nJSON形式で出力してください。"

        return prompt
    }
}
