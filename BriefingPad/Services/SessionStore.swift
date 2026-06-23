import Foundation

struct LLMResult: Codable, Identifiable, Hashable {
    let id: UUID
    let observationMatches: [ItemMatch]
    let positiveMatches: [ItemMatch]
    let sourceChunkId: UUID
    let sourceChunkText: String
    let sourceChunkStartTime: Double
    let sourceChunkEndTime: Double

    init(
        id: UUID = UUID(),
        observationMatches: [ItemMatch],
        positiveMatches: [ItemMatch],
        sourceChunkId: UUID,
        sourceChunkText: String,
        sourceChunkStartTime: Double,
        sourceChunkEndTime: Double
    ) {
        self.id = id
        self.observationMatches = observationMatches
        self.positiveMatches = positiveMatches
        self.sourceChunkId = sourceChunkId
        self.sourceChunkText = sourceChunkText
        self.sourceChunkStartTime = sourceChunkStartTime
        self.sourceChunkEndTime = sourceChunkEndTime
    }
}

struct FinalSummary: Codable, Hashable {
    let text: String
    let adoptedItemIds: [String]
    let sourceLLMResultIds: [UUID]
}

struct PartRun: Codable {
    let partId: String
    var audioFileNames: [String] = []
    var transcript: [TranscriptSegment] = []
    var llmResults: [LLMResult] = []
    var finalSummary: FinalSummary?
    var elapsedTime: TimeInterval = 0
    var isFinished: Bool = false

    enum CodingKeys: String, CodingKey {
        case partId, audioFileNames, audioFileName, transcript, llmResults, finalSummary, elapsedTime, isFinished
    }

    init(partId: String) {
        self.partId = partId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        partId = try container.decode(String.self, forKey: .partId)
        transcript = try container.decode([TranscriptSegment].self, forKey: .transcript)
        llmResults = try container.decode([LLMResult].self, forKey: .llmResults)
        finalSummary = try container.decodeIfPresent(FinalSummary.self, forKey: .finalSummary)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        isFinished = try container.decode(Bool.self, forKey: .isFinished)

        if let names = try container.decodeIfPresent([String].self, forKey: .audioFileNames) {
            audioFileNames = names
        } else if let oldName = try container.decodeIfPresent(String.self, forKey: .audioFileName) {
            audioFileNames = [oldName]
        } else {
            audioFileNames = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partId, forKey: .partId)
        try container.encode(audioFileNames, forKey: .audioFileNames)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(llmResults, forKey: .llmResults)
        try container.encodeIfPresent(finalSummary, forKey: .finalSummary)
        try container.encode(elapsedTime, forKey: .elapsedTime)
        try container.encode(isFinished, forKey: .isFinished)
    }
}

struct SavedSession: Codable {
    let sessionId: String
    var templateSnapshot: BriefingSession
    var updatedAt: Date
    var notionPageId: String?
    var errorHistory: [String] = []
    var partRuns: [String: PartRun] = [:] // partId -> PartRun
}

protocol SessionStoreProtocol {
    func listSessions() async throws -> [String]
    func loadSession(sessionId: String) async throws -> SavedSession?
    func saveSession(_ session: SavedSession) async throws
    func deleteSession(sessionId: String) async throws
    func deleteAudio(sessionId: String, partId: String) async throws
    func deleteTranscript(sessionId: String, partId: String) async throws
    func deleteLLMResults(sessionId: String, partId: String) async throws
    func getAudioURL(sessionId: String, partId: String, recordingId: String) -> URL
    func getPartDirectory(sessionId: String, partId: String) -> URL
}

class FileSessionStore: SessionStoreProtocol {
    func listSessions() async throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return contents
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
    }

    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        if let rootURL = rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = appSupport.appendingPathComponent("BriefingPad/sessions", isDirectory: true)
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    private func sanitize(_ id: String) -> String {
        // Simple sanitization: allow alphanumeric, hyphen, underscore
        return id.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }

    private func sessionDirectory(for sessionId: String) -> URL {
        rootURL.appendingPathComponent(sanitize(sessionId), isDirectory: true)
    }

    private func partDirectory(for sessionId: String, partId: String) -> URL {
        sessionDirectory(for: sessionId).appendingPathComponent("parts/\(sanitize(partId))", isDirectory: true)
    }

    func getAudioURL(sessionId: String, partId: String, recordingId: String) -> URL {
        partDirectory(for: sessionId, partId: partId).appendingPathComponent("audio_\(sanitize(recordingId)).m4a")
    }

    func getPartDirectory(sessionId: String, partId: String) -> URL {
        partDirectory(for: sessionId, partId: partId)
    }

    func loadSession(sessionId: String) async throws -> SavedSession? {
        let manifestURL = sessionDirectory(for: sessionId).appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        var session = try decoder.decode(SavedSession.self, from: data)

        // Load part data from separate files
        for part in session.templateSnapshot.parts {
            let partDir = partDirectory(for: sessionId, partId: part.id)

            var partRun = session.partRuns[part.id] ?? PartRun(partId: part.id)

            // Transcript
            let transcriptURL = partDir.appendingPathComponent("transcript.json")
            if let transcriptData = try? Data(contentsOf: transcriptURL) {
                partRun.transcript = try decoder.decode([TranscriptSegment].self, from: transcriptData)
            }

            // LLM Results
            let llmResultsURL = partDir.appendingPathComponent("llm_results.json")
            if let llmResultsData = try? Data(contentsOf: llmResultsURL) {
                partRun.llmResults = try decoder.decode([LLMResult].self, from: llmResultsData)
            }

            // Final Summary
            let finalSummaryURL = partDir.appendingPathComponent("final_summary.json")
            if let finalSummaryData = try? Data(contentsOf: finalSummaryURL) {
                partRun.finalSummary = try decoder.decode(FinalSummary.self, from: finalSummaryData)
            }

            // Check for audio files
            partRun.audioFileNames = partRun.audioFileNames.filter { fileName in
                let audioURL = partDir.appendingPathComponent(fileName)
                return FileManager.default.fileExists(atPath: audioURL.path)
            }

            session.partRuns[part.id] = partRun
        }

        return session
    }

    func saveSession(_ session: SavedSession) async throws {
        let sessionDir = sessionDirectory(for: session.sessionId)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Save manifest (without detailed part data if we want to follow "separation" strictly,
        // but the struct includes them. To separate, we'd need a Manifest struct or strip them.)
        // Let's strip them from manifest.json to avoid redundancy and follow the prompt.

        var manifest = session
        manifest.partRuns = session.partRuns.mapValues { run in
            var stripped = run
            stripped.transcript = []
            stripped.llmResults = []
            stripped.finalSummary = nil
            return stripped
        }

        let manifestURL = sessionDir.appendingPathComponent("manifest.json")
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL)

        // Save part-specific files
        for (partId, partRun) in session.partRuns {
            let partDir = partDirectory(for: session.sessionId, partId: partId)
            try FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)

            // Transcript
            let transcriptURL = partDir.appendingPathComponent("transcript.json")
            let transcriptData = try encoder.encode(partRun.transcript)
            try transcriptData.write(to: transcriptURL)

            // LLM Results
            let llmResultsURL = partDir.appendingPathComponent("llm_results.json")
            let llmResultsData = try encoder.encode(partRun.llmResults)
            try llmResultsData.write(to: llmResultsURL)

            // Final Summary
            if let finalSummary = partRun.finalSummary {
                let finalSummaryURL = partDir.appendingPathComponent("final_summary.json")
                let finalSummaryData = try encoder.encode(finalSummary)
                try finalSummaryData.write(to: finalSummaryURL)
            } else {
                let finalSummaryURL = partDir.appendingPathComponent("final_summary.json")
                try? FileManager.default.removeItem(at: finalSummaryURL)
            }
        }
    }

    func deleteSession(sessionId: String) async throws {
        let sessionDir = sessionDirectory(for: sessionId)
        if FileManager.default.fileExists(atPath: sessionDir.path) {
            try FileManager.default.removeItem(at: sessionDir)
        }
    }

    func deleteAudio(sessionId: String, partId: String) async throws {
        let partDir = partDirectory(for: sessionId, partId: partId)
        let files = try? FileManager.default.contentsOfDirectory(at: partDir, includingPropertiesForKeys: nil)
        let audioFiles = files?.filter { $0.lastPathComponent.hasPrefix("audio_") && $0.pathExtension == "m4a" }
        for url in audioFiles ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteTranscript(sessionId: String, partId: String) async throws {
        let transcriptURL = partDirectory(for: sessionId, partId: partId).appendingPathComponent("transcript.json")
        if FileManager.default.fileExists(atPath: transcriptURL.path) {
            try FileManager.default.removeItem(at: transcriptURL)
        }
    }

    func deleteLLMResults(sessionId: String, partId: String) async throws {
        let llmURL = partDirectory(for: sessionId, partId: partId).appendingPathComponent("llm_results.json")
        let summaryURL = partDirectory(for: sessionId, partId: partId).appendingPathComponent("final_summary.json")

        if FileManager.default.fileExists(atPath: llmURL.path) {
            try FileManager.default.removeItem(at: llmURL)
        }
        if FileManager.default.fileExists(atPath: summaryURL.path) {
            try FileManager.default.removeItem(at: summaryURL)
        }
    }
}
