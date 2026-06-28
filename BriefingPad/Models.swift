import Foundation

enum AnalysisItemStatus: String, Codable, Hashable, Comparable {
    case hidden
    case candidate
    case strong

    private var priority: Int {
        switch self {
        case .hidden: return 0
        case .candidate: return 1
        case .strong: return 2
        }
    }

    static func < (lhs: AnalysisItemStatus, rhs: AnalysisItemStatus) -> Bool {
        return lhs.priority < rhs.priority
    }

    var displayLabel: String {
        switch self {
        case .hidden:
            return "ー"
        case .candidate:
            return "🟠"
        case .strong:
            return "🟢"
        }
    }
}

struct AnalysisItemState: Codable, Hashable {
    var confidence: Double
    var shortEvidence: String
    var status: AnalysisItemStatus
    var lastUpdatedAt: Date

    static func hidden(at date: Date = .now) -> Self {
        Self(
            confidence: 0,
            shortEvidence: "",
            status: .hidden,
            lastUpdatedAt: date
        )
    }
}

struct LearningPoint: Identifiable, Codable, Hashable {
    let id: String
    let text: String
}

protocol SummaryItemProtocol: Identifiable {
    var id: String { get }
    var text: String { get }
}

struct ObservationItem: SummaryItemProtocol, Codable, Hashable {
    let id: String
    let text: String
}

struct PositiveItem: SummaryItemProtocol, Codable, Hashable {
    let id: String
    let text: String
}

struct PartAnalysisState: Codable, Hashable {
    var observationItemStates: [String: AnalysisItemState]
    var positiveItemStates: [String: AnalysisItemState]

    static func initial(
        observationItems: [ObservationItem],
        positiveItems: [PositiveItem],
        at date: Date = .now
    ) -> Self {
        let observationItemStates = Dictionary(
            uniqueKeysWithValues: observationItems.map { ($0.id, AnalysisItemState.hidden(at: date)) }
        )
        let positiveItemStates = Dictionary(
            uniqueKeysWithValues: positiveItems.map { ($0.id, AnalysisItemState.hidden(at: date)) }
        )

        return Self(
            observationItemStates: observationItemStates,
            positiveItemStates: positiveItemStates
        )
    }
}

struct PartDefinition: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String
    let durationMinutes: Int?
    let setting: String?
    let rawMarkdown: String
    let learningPoints: [LearningPoint]
    let observationItems: [ObservationItem]
    let positiveItems: [PositiveItem]
    var aiMemo: String
    var aiMemoBlockId: String?
    var lastSyncedHash: String?
    var lastSyncedTime: String?
    var aiMemoGenerationError: String?
    var analysisState: PartAnalysisState

    init(
        id: String,
        number: Int,
        title: String,
        durationMinutes: Int?,
        setting: String?,
        rawMarkdown: String,
        learningPoints: [LearningPoint],
        observationItems: [ObservationItem],
        positiveItems: [PositiveItem],
        aiMemo: String = "",
        aiMemoBlockId: String? = nil,
        lastSyncedHash: String? = nil,
        lastSyncedTime: String? = nil,
        aiMemoGenerationError: String? = nil,
        analysisState: PartAnalysisState? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.durationMinutes = durationMinutes
        self.setting = setting
        self.rawMarkdown = rawMarkdown
        self.learningPoints = learningPoints
        self.observationItems = observationItems
        self.positiveItems = positiveItems
        self.aiMemo = aiMemo
        self.aiMemoBlockId = aiMemoBlockId
        self.lastSyncedHash = lastSyncedHash
        self.lastSyncedTime = lastSyncedTime
        self.aiMemoGenerationError = aiMemoGenerationError
        self.analysisState = analysisState ?? PartAnalysisState.initial(
            observationItems: observationItems,
            positiveItems: positiveItems
        )
    }
}

enum SessionSortOrder: String, CaseIterable, Identifiable {
    case nameAsc, nameDesc
    case updatedAsc, updatedDesc
    case createdAsc, createdDesc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nameAsc:     return "名前 (昇順)"
        case .nameDesc:    return "名前 (降順)"
        case .updatedAsc:  return "更新日時 (古い順)"
        case .updatedDesc: return "更新日時 (新しい順)"
        case .createdAsc:  return "作成日時 (古い順)"
        case .createdDesc: return "作成日時 (新しい順)"
        }
    }
}

struct BriefingSession: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var parts: [PartDefinition]
    var createdAt: Date
    var updatedAt: Date

    init(id: String, name: String, parts: [PartDefinition], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, parts, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parts = try container.decode([PartDefinition].self, forKey: .parts)

        // Deterministic migration for legacy sessions
        let defaultCreatedAt = decoder.userInfo[.sessionCreatedAt] as? Date ?? Date(timeIntervalSince1970: 1704067200) // 2024-01-01
        let defaultUpdatedAt = decoder.userInfo[.sessionUpdatedAt] as? Date ?? defaultCreatedAt

        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? defaultCreatedAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? defaultUpdatedAt
    }
}

extension CodingUserInfoKey {
    static let sessionCreatedAt = CodingUserInfoKey(rawValue: "sessionCreatedAt")!
    static let sessionUpdatedAt = CodingUserInfoKey(rawValue: "sessionUpdatedAt")!
}

struct LocalBriefingCatalog: Codable {
    let sessions: [BriefingSession]
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionId: String
    let partId: String
    let text: String
    let isFinal: Bool
    let startTime: Double
    let endTime: Double
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: String,
        partId: String,
        text: String,
        isFinal: Bool,
        startTime: Double,
        endTime: Double,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.partId = partId
        self.text = text
        self.isFinal = isFinal
        self.startTime = startTime
        self.endTime = endTime
        self.receivedAt = receivedAt
    }
}

struct TranscriptChunk: Identifiable, Codable, Hashable {
    let id: UUID
    let partId: String
    let text: String
    let startTime: Double
    let endTime: Double

    init(
        id: UUID = UUID(),
        partId: String,
        text: String,
        startTime: Double,
        endTime: Double
    ) {
        self.id = id
        self.partId = partId
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct PartState: Codable, Hashable {
    var transcript: [TranscriptSegment] = []
    var isFinished: Bool = false
    var elapsedTime: TimeInterval = 0
    var llmResults: [LLMResult] = []
    var finalSummary: FinalSummary?
    var audioFileNames: [String] = []

    enum CodingKeys: String, CodingKey {
        case transcript, isFinished, elapsedTime, llmResults, finalSummary, audioFileNames, audioFileName
    }

    init(
        transcript: [TranscriptSegment] = [],
        isFinished: Bool = false,
        elapsedTime: TimeInterval = 0,
        llmResults: [LLMResult] = [],
        finalSummary: FinalSummary? = nil,
        audioFileNames: [String] = []
    ) {
        self.transcript = transcript
        self.isFinished = isFinished
        self.elapsedTime = elapsedTime
        self.llmResults = llmResults
        self.finalSummary = finalSummary
        self.audioFileNames = audioFileNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try container.decode([TranscriptSegment].self, forKey: .transcript)
        isFinished = try container.decode(Bool.self, forKey: .isFinished)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        llmResults = try container.decode([LLMResult].self, forKey: .llmResults)
        finalSummary = try container.decodeIfPresent(FinalSummary.self, forKey: .finalSummary)

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
        try container.encode(transcript, forKey: .transcript)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encode(elapsedTime, forKey: .elapsedTime)
        try container.encode(llmResults, forKey: .llmResults)
        try container.encodeIfPresent(finalSummary, forKey: .finalSummary)
        try container.encode(audioFileNames, forKey: .audioFileNames)
    }
}

struct SessionState: Codable, Hashable {
    var partStates: [String: PartState] = [:] // partId -> PartState
}
