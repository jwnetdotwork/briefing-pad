import Foundation

struct PromptBuilder {
    static func buildSystemPrompt() -> String {
        return """
        あなたは「生活と奉仕の集会」の実演に対する短評を準備する補助者です。
        提供された文字起こしデータ（全文および最新の追加分）を分析し、特定の「観察メモ」および「良かった点候補」に該当する箇所があるかを判定してください。

        以下の制約を厳守してJSON形式で回答してください：
        1. 指定された itemId 以外は返さないこと。
        2. 各項目について、確信度（confidence: 0.0〜1.0）と、その根拠となる短い証拠（shortEvidence）を抽出すること。
        3. JSONフォーマットは以下の通りとすること：
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

    static func buildOneLinerSystemPrompt() -> String {
        return """
        あなたは「生活と奉仕の集会」の実演に対する短評を準備する補助者です。
        提供されるパート情報、学習ポイント、および実演の文字起こし原稿、そして分析によって得られた「良かった点」や「観察事項」の候補を基に、約1分間の短評に使える「コメント用素材」をコンパクトに箇条書きでまとめてください。

        # 出力してほしいもの
        - 約1分間の短評に使える素材（箇条書き）を出力する。
        - 次の流れを意識する。
          1. 最初の温かい褒め言葉
          2. どこがどのように良かったか
          3. 学習ポイントをどのように反映していたか
          4. 必要なら、さらにどんなふうに取り組むとよいか
          5. 最後に、聞いている皆が当てはめられる学びの一言

        # 重要な注意点
        - 文字起こし原稿には誤字脱字や聞き取り違いが含まれている可能性があるので、文脈から自然に補って判断する。
        - 実演者と相手の発言が区別されていない場合があるので、会話の流れからどちらの発言かを見極める。
        - 学習ポイントがはっきり反映されていない場合は、無理に学習ポイントに結び付けて褒めない。
        - その場合でも、実演の中で良かった点、例えば温かさ、自然さ、相手への気遣い、聞く姿勢、聖句や出版物への導き方などを見つけて褒める。
        - 全体として、実演者が励まされる温かい短評にする。
        - 「さらに取り組むといい点」は必須ではない。
        - 確実に改善した方がよい点がある場合だけ、やわらかく1点だけ含める。
        - 自信がない場合は、改善点は出さない。
        - 批判的、断定的、細かすぎる指摘は避ける。
        - 実演者本人を評価しすぎるより、「この点から学べる」と会衆全体に益がある形にする。

        # 出力形式
        次のような箇条書きで、5項目以内にまとめてください。余計な説明や、挨拶、Markdownのコードブロックは含めず、本文のみを出力してください｡

        - まず、〇〇がとても良かった
        - 特に、〇〇という場面で、相手に〇〇が伝わっていた
        - 学習ポイントの〇〇についても、〇〇という形でよく表れていた
        - もし加えるなら、〇〇するとさらに〇〇になる｡
        - 私たちも、〇〇を学べる

        # 文体
        - 短評でそのまま話せる自然な日本語
        - 温かく、簡潔に
        - 約1分で話せる分量
        - 箇条書きのみ
        """
    }

    static func buildOneLinerUserPrompt(
        partInfo: PartDefinition,
        fullTranscript: String,
        positives: [SummarizedItem],
        observations: [SummarizedItem]
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

        prompt += "\n## 分析済みの候補（良かった点）\n"
        if positives.isEmpty {
            prompt += "(なし)\n"
        } else {
            for item in positives {
                prompt += "- \(item.text) (根拠: \(item.evidence))\n"
            }
        }

        prompt += "\n## 分析済みの候補（観察事項）\n"
        if observations.isEmpty {
            prompt += "(なし)\n"
        } else {
            for item in observations {
                prompt += "- \(item.text) \(item.evidence)\n"
            }
        }

        prompt += "\n## 実演の文字起こし原稿（全文）\n"
        prompt += fullTranscript + "\n"

        prompt += "\n## 回答\n箇条書きのコメント用素材のみを出力してください。"

        return prompt
    }
}
