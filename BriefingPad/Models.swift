import Foundation

enum AnalysisItemStatus: String, Codable, Hashable {
    case hidden
    case candidate
    case strong

    var displayLabel: String {
        switch self {
        case .hidden:
            return "非表示 hidden"
        case .candidate:
            return "○ candidate"
        case .strong:
            return "◎ strong"
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

struct ObservationItem: Identifiable, Codable, Hashable {
    let id: String
    let text: String
}

struct PositiveItem: Identifiable, Codable, Hashable {
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
        self.analysisState = analysisState ?? PartAnalysisState.initial(
            observationItems: observationItems,
            positiveItems: positiveItems
        )
    }
}

struct BriefingSession: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    var parts: [PartDefinition]
}

struct LocalBriefingCatalog: Codable {
    let sessions: [BriefingSession]
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isFinal: Bool
    let startTime: Double?
    let endTime: Double?
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isFinal: Bool,
        startTime: Double? = nil,
        endTime: Double? = nil,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.startTime = startTime
        self.endTime = endTime
        self.receivedAt = receivedAt
    }
}

struct PartState: Codable, Hashable {
    var transcript: [TranscriptSegment] = []
}

struct SessionState: Codable, Hashable {
    var partStates: [String: PartState] = [:] // partId -> PartState
}
