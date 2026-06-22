import Foundation

class OpenAILLMService: LLMServiceProtocol {
    private let keychainService: KeychainServiceProtocol
    private let model: String
    private let url = URL(string: "https://api.openai.com/v1/chat/completions")!

    static let defaultModel = "gpt-5.4-mini-2026-03-17"

    init(keychainService: KeychainServiceProtocol, model: String = defaultModel) {
        self.keychainService = keychainService
        self.model = model
    }

    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition
    ) async throws -> AnalysisResult {
        guard let apiKey = keychainService.load(key: KeychainKeys.openaiApiKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw LLMError.missingApiKey
        }

        let systemPrompt = PromptBuilder.buildSystemPrompt()
        let userPrompt = PromptBuilder.buildUserPrompt(
            fullTranscript: fullTranscript,
            newChunk: newChunk,
            partInfo: partInfo
        )

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.0,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            throw LLMError.apiError(status: errorStatus, body: errorBody)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        // Strict parsing as requested
        do {
            let result = try JSONDecoder().decode(AnalysisResult.self, from: content.data(using: .utf8)!)

            // Filter out unknown itemIds and invalid confidence values
            let knownObsIds = Set(partInfo.observationItems.map { $0.id })
            let knownPosIds = Set(partInfo.positiveItems.map { $0.id })

            let filteredResult = AnalysisResult(
                observationMatches: result.observationMatches.filter {
                    knownObsIds.contains($0.itemId) && $0.confidence.isFinite && (0.0...1.0).contains($0.confidence)
                },
                positiveMatches: result.positiveMatches.filter {
                    knownPosIds.contains($0.itemId) && $0.confidence.isFinite && (0.0...1.0).contains($0.confidence)
                }
            )

            return filteredResult
        } catch {
            throw LLMError.parseError(error.localizedDescription)
        }
    }

    func generateOneLiner(summarizedPoints: [String]) async throws -> String {
        guard let apiKey = keychainService.load(key: KeychainKeys.openaiApiKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw LLMError.missingApiKey
        }

        let systemPrompt = PromptBuilder.buildOneLinerSystemPrompt()
        let userPrompt = PromptBuilder.buildOneLinerUserPrompt(summarizedPoints: summarizedPoints)

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
            "max_completion_tokens": 1024
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            throw LLMError.apiError(status: errorStatus, body: errorBody)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: Error {
    case missingApiKey
    case apiError(status: Int, body: String)
    case invalidResponse
    case parseError(String)
}

struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
