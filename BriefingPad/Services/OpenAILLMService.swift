import Foundation

class OpenAILLMService: LLMServiceProtocol {
    private let keychainService: KeychainServiceProtocol
    private let session: URLSession
    private let defaultModel: String
    private let timeout: TimeInterval
    private var url: URL {
        let base = UserDefaults.standard.string(forKey: "customApiEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultUrl = URL(string: "https://api.openai.com/v1/chat/completions")!
        if base.isEmpty { return defaultUrl }
        do {
            let validated = try EndpointValidator.validate(urlString: base)
            return validated.appendingPathComponent("chat/completions")
        } catch {
            return defaultUrl
        }
    }

    private var model: String {
        let savedModel = UserDefaults.standard.string(forKey: "customModelName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return savedModel.isEmpty ? defaultModel : savedModel
    }

    static let hardcodedDefaultModel = "gpt-5.4-mini-2026-03-17"

    init(
        keychainService: KeychainServiceProtocol,
        session: URLSession = .shared,
        model: String = hardcodedDefaultModel,
        timeout: TimeInterval = 30.0
    ) {
        self.keychainService = keychainService
        self.session = session
        self.defaultModel = model
        self.timeout = timeout
    }

    func analyzeTranscript(
        fullTranscript: String,
        newChunk: String,
        partInfo: PartDefinition,
        localeIdentifier: String
    ) async throws -> AnalysisResult {
        try validateEndpoint()
        guard let apiKey = keychainService.load(key: KeychainKeys.openaiApiKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw LLMError.missingApiKey
        }

        let systemPrompt = PromptBuilder.buildSystemPrompt(localeIdentifier: localeIdentifier)
        let userPrompt = PromptBuilder.buildUserPrompt(
            fullTranscript: fullTranscript,
            newChunk: newChunk,
            partInfo: partInfo,
            localeIdentifier: localeIdentifier
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
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)

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

    /// 箇条書きのコメント用素材を生成する
    func generateOneLiner(
        partInfo: PartDefinition,
        fullTranscript: String,
        positives: [SummarizedItem],
        observations: [SummarizedItem],
        localeIdentifier: String
    ) async throws -> String {
        try validateEndpoint()
        guard let apiKey = keychainService.load(key: KeychainKeys.openaiApiKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw LLMError.missingApiKey
        }

        let systemPrompt = PromptBuilder.buildOneLinerSystemPrompt(localeIdentifier: localeIdentifier)
        let userPrompt = PromptBuilder.buildOneLinerUserPrompt(
            partInfo: partInfo,
            fullTranscript: fullTranscript,
            positives: positives,
            observations: observations,
            localeIdentifier: localeIdentifier
        )

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
        request.timeoutInterval = timeout

        return try await withThrowingTaskGroup(of: String.self) { [timeout] group in
            group.addTask { [session] in
                do {
                    let (data, response) = try await session.data(for: request)

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
                } catch {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        throw LLMError.timeout
                    }
                    throw error
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LLMError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func validateEndpoint() throws {
        let base = UserDefaults.standard.string(forKey: "customApiEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty { return }
        do {
            _ = try EndpointValidator.validate(urlString: base)
        } catch {
            throw LLMError.invalidEndpoint(error.localizedDescription)
        }
    }
}

enum LLMError: Error, LocalizedError {
    case missingApiKey
    case apiError(status: Int, body: String)
    case invalidResponse
    case parseError(String)
    case timeout
    case invalidEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return NSLocalizedString("llm.error.missingApiKey", comment: "API key is missing")
        case .apiError(let status, _):
            return String(format: NSLocalizedString("llm.error.apiErrorFormat", comment: "API error with status"), status)
        case .invalidResponse:
            return NSLocalizedString("llm.error.invalidResponse", comment: "Invalid response from AI")
        case .parseError(let message):
            return String(format: NSLocalizedString("llm.error.parseErrorFormat", comment: "Parse error with message"), message)
        case .timeout:
            return NSLocalizedString("llm.error.timeout", comment: "Request timed out")
        case .invalidEndpoint(let message):
            return String(format: NSLocalizedString("llm.error.invalidEndpointFormat", comment: "Invalid endpoint with message"), message)
        }
    }
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
