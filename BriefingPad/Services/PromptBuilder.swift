import Foundation

struct PromptBuilder {
    static func languageName(from localeIdentifier: String) -> String {
        let locale = Locale(identifier: "en_US")
        return locale.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
    }

    static func buildSystemPrompt(localeIdentifier: String) -> String {
        let language = languageName(from: localeIdentifier)
        return """
        You are an assistant preparing brief comments for a "Life and Ministry Meeting" demonstration.
        Analyze the provided transcript data (full text and latest addition) to determine if there are parts that correspond to specific "Observation Notes" and "Positive Item Candidates".

        The user prompt will include previous judgment results.
        Treat already judged items as a foundation and update them only if necessary.
        Prioritize checking unjudged items and re-evaluate existing judgments only when new material is available.

        Strictly adhere to the following constraints and respond in JSON format:
        1. Do not return any itemId other than those specified.
        2. For each item, extract a confidence level (confidence: 0.0 to 1.0) and a short piece of evidence (shortEvidence) that serves as the basis.
        3. The JSON format must be as follows:
        {
          "observationMatches": [
            { "itemId": "obs-1", "confidence": 0.9, "shortEvidence": "evidence text" }
          ],
          "positiveMatches": [
            { "itemId": "pos-1", "confidence": 0.7, "shortEvidence": "evidence text" }
          ]
        }
        4. Do not include any extra explanations or Markdown code blocks (```json ... ```); output only pure JSON.
        5. Important: Output the "shortEvidence" in \(language).
        """
    }

    static func buildUserPrompt(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition,
        localeIdentifier: String
    ) -> String {
        let language = languageName(from: localeIdentifier)
        var prompt = "## Current Part Information\n"
        prompt += "Title: \(partInfo.title)\n"
        if let setting = partInfo.setting {
            prompt += "Setting: \(setting)\n"
        }

        prompt += "\n## Learning Points\n"
        for lp in partInfo.learningPoints {
            prompt += "- \(lp.text)\n"
        }

        prompt += "\n## Previous Results: Observation Items\n"
        for item in partInfo.observationItems {
            let state = partInfo.analysisState.observationItemStates[item.id] ?? .hidden()
            prompt += "- id: \(item.id), Content: \(item.text), "
            if state.status == .hidden {
                prompt += "Status: hidden (unjudged)\n"
            } else {
                prompt += "Status: \(state.status.rawValue), Confidence: \(state.confidence), Evidence: \(state.shortEvidence)\n"
            }
        }

        prompt += "\n## Previous Results: Positive Item Candidates\n"
        for item in partInfo.positiveItems {
            let state = partInfo.analysisState.positiveItemStates[item.id] ?? .hidden()
            prompt += "- id: \(item.id), Content: \(item.text), "
            if state.status == .hidden {
                prompt += "Status: hidden (unjudged)\n"
            } else {
                prompt += "Status: \(state.status.rawValue), Confidence: \(state.confidence), Evidence: \(state.shortEvidence)\n"
            }
        }

        prompt += "\n## Full Transcript (up to now)\n"
        prompt += fullTranscript + "\n"

        prompt += "\n## Latest Added Transcript (target for this analysis)\n"
        prompt += newChunk + "\n"

        prompt += "\n## Response\nPlease output in JSON format. Ensure all evidence text is in \(language)."

        return prompt
    }

    static func buildOneLinerSystemPrompt(localeIdentifier: String) -> String {
        let language = languageName(from: localeIdentifier)
        return """
        You are an assistant preparing brief comments for a "Life and Ministry Meeting" demonstration.
        Based on the provided part information, learning points, transcript of the demonstration, and candidates for "positive points" and "observation items" obtained through analysis, please summarize "comment materials" that can be used for a brief comment of about 1 minute in a compact bulleted list.

        # What to Output
        - Output materials (bullet points) that can be used for a brief comment of about 1 minute.
        - Be mindful of the following flow:
          1. Initial warm words of praise
          2. Where and how it was good
          3. How learning points were reflected
          4. If necessary, how to work on it further
          5. Finally, a word of learning that everyone listening can apply

        # Important Notes
        - The transcript may contain typos or mishearings, so judge naturally by supplementing from the context.
        - Speaker and partner utterances may not be distinguished, so identify which speech belongs to whom from the flow of conversation.
        - If the learning points are not clearly reflected, do not force a connection to the learning points to praise.
        - Even in that case, find and praise good points in the demonstration, such as warmth, naturalness, consideration for the partner, listening attitude, how to lead to scriptures or publications, etc.
        - Overall, make it a warm brief comment that encourages the demonstrator.
        - "Points to work on further" are not mandatory.
        - Include only one point softly if there is something that should definitely be improved.
        - If you are not confident, do not output improvement points.
        - Avoid critical, dogmatic, or overly detailed points.
        - Rather than evaluating the demonstrator too much, make it in a form that benefits the whole congregation, saying "We can learn from this point."

        # Output Format
        Summarize in no more than 5 bullet points in the following format. Do not include extra explanations, greetings, or Markdown code blocks; output only the body text.
        The content must be written in \(language).

        - [Warm praise for something that was very good]
        - [Specific scene where something was good and conveyed to the partner]
        - [How a learning point was well expressed]
        - [A point to work on further (optional)]
        - [A lesson for the whole congregation]

        # Style
        - Natural \(language) that can be used as-is in a brief comment.
        - Warm and concise.
        - Amount that can be spoken in about 1 minute.
        - Bullet points only.
        """
    }

    static func buildOneLinerUserPrompt(
        partInfo: PartDefinition,
        fullTranscript: String,
        positives: [SummarizedItem],
        observations: [SummarizedItem],
        localeIdentifier: String
    ) -> String {
        let language = languageName(from: localeIdentifier)
        var prompt = "## Current Part Information\n"
        prompt += "Title: \(partInfo.title)\n"
        if let setting = partInfo.setting {
            prompt += "Setting: \(setting)\n"
        }

        prompt += "\n## Learning Points\n"
        for lp in partInfo.learningPoints {
            prompt += "- \(lp.text)\n"
        }

        prompt += "\n## Analyzed Candidates (Positive Points)\n"
        if positives.isEmpty {
            prompt += "(None)\n"
        } else {
            for item in positives {
                prompt += "- \(item.text) (Evidence: \(item.evidence))\n"
            }
        }

        prompt += "\n## Analyzed Candidates (Observation Items)\n"
        if observations.isEmpty {
            prompt += "(None)\n"
        } else {
            for item in observations {
                prompt += "- \(item.text) \(item.evidence)\n"
            }
        }

        prompt += "\n## Demonstration Transcript (Full Text)\n"
        prompt += fullTranscript + "\n"

        prompt += "\n## Response\nPlease output only the bulleted comment materials in \(language)."

        return prompt
    }
}
