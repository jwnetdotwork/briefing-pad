import SwiftUI

struct SectionContainer<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            content
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let errorMessage: String?

    @State private var isAtBottom = true

    var body: some View {
        SectionContainer("文字起こし") {
            VStack(alignment: .leading, spacing: 4) {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.bottom, 4)
                }

                if segments.isEmpty {
                    Text("（録音を開始するとここに文字起こしが表示されます）")
                        .foregroundColor(.secondary)
                        .font(.body)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(segments) { segment in
                                    Text(segment.text)
                                        .font(.body)
                                        .foregroundStyle(segment.isFinal ? .primary : .secondary)
                                        .italic(!segment.isFinal)
                                        .id(segment.id)
                                }
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("scroll")).maxY) {
                                            let visibleHeight = 200.0
                                            let scrollOffset = geo.frame(in: .named("scroll")).maxY
                                            isAtBottom = scrollOffset < visibleHeight + 50
                                        }
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .frame(height: 200)
                        .onChange(of: segments) {
                            if isAtBottom {
                                if let last = segments.last {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LearningPointsView: View {
    let points: [LearningPoint]

    var body: some View {
        SectionContainer("学習ポイント") {
            VStack(alignment: .leading, spacing: 4) {
                if points.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(points) { point in
                        Text("・\(point.text)")
                    }
                }
            }
        }
    }
}

struct ObservationItemsView: View {
    let items: [ObservationItem]
    let state: [String: AnalysisItemState]

    var body: some View {
        SectionContainer("観察メモ") {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        let itemState = state[item.id] ?? .hidden()
                        let isStrong = itemState.status == .strong
                        let isCandidate = itemState.status == .candidate

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("・\(item.text)")
                                    .foregroundColor((isStrong || isCandidate) ? .primary : .secondary)

                                Spacer(minLength: 12)

                                if isStrong || isCandidate {
                                    Text(itemState.status.displayLabel)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !itemState.shortEvidence.isEmpty && (isStrong || isCandidate) {
                                Text(itemState.shortEvidence)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PositiveItemsView: View {
    let items: [PositiveItem]
    let state: [String: AnalysisItemState]

    private var displayItems: [(item: PositiveItem, state: AnalysisItemState)] {
        items.compactMap { item -> (item: PositiveItem, state: AnalysisItemState)? in
            let itemState = state[item.id] ?? .hidden()
            guard itemState.status != .hidden else { return nil }
            return (item, itemState)
        }
        .sorted { $0.state.confidence > $1.state.confidence }
        .prefix(2)
        .map { $0 }
    }

    var body: some View {
        SectionContainer("良かった点候補") {
            VStack(alignment: .leading, spacing: 8) {
                if displayItems.isEmpty {
                    Text("（該当なし）")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(displayItems, id: \.item.id) { pair in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("・\(pair.item.text)")
                                    .font(.body.bold())

                                Spacer(minLength: 12)

                                Text(pair.state.status.displayLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if !pair.state.shortEvidence.isEmpty {
                                Text(pair.state.shortEvidence)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CommentMaterialView: View {
    let aiMemo: String
    let isFinalizing: Bool

    var body: some View {
        SectionContainer("🤖 AIメモ") {
            VStack(alignment: .leading, spacing: 8) {
                if isFinalizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("確定メモ生成中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(aiMemo.isEmpty && !isFinalizing ? "（文字起こしが進むとここにAIメモが表示されます）" : aiMemo)
                    .font(.body)
                    .lineSpacing(4)
            }
        }
    }
}

struct SectionViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TranscriptView(
                segments: [
                    TranscriptSegment(text: "確定したテキスト", isFinal: true),
                    TranscriptSegment(text: "未確定のテキスト", isFinal: false)
                ],
                errorMessage: nil
            )
            LearningPointsView(points: [
                LearningPoint(id: "lp-1", text: "テスト1"),
                LearningPoint(id: "lp-2", text: "テスト2")
            ])
            ObservationItemsView(
                items: [
                    ObservationItem(id: "obs-1", text: "観察1"),
                    ObservationItem(id: "obs-2", text: "観察2")
                ],
                state: [
                    "obs-1": AnalysisItemState(
                        confidence: 0.8,
                        shortEvidence: "根拠",
                        status: .strong,
                        lastUpdatedAt: .now
                    )
                ]
            )
            PositiveItemsView(
                items: [
                    PositiveItem(id: "pos-1", text: "良かった点1")
                ],
                state: [:]
            )
            CommentMaterialView(aiMemo: "AIメモ", isFinalizing: false)
        }
    }
}
