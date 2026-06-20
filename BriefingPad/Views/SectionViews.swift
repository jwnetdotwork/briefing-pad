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
    let text: String

    var body: some View {
        SectionContainer("文字起こし") {
            Text(text)
                .font(.body)
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
            VStack(alignment: .leading, spacing: 12) {
                if items.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        let itemState = state[item.id] ?? .hidden()

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("・\(item.text)")
                                Spacer(minLength: 12)
                                Text(itemState.status.displayLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if !itemState.shortEvidence.isEmpty {
                                Text(itemState.shortEvidence)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("confidence \(Int(itemState.confidence * 100))% / 更新 \(itemState.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
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

    var body: some View {
        SectionContainer("良かった点候補") {
            VStack(alignment: .leading, spacing: 12) {
                if items.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        let itemState = state[item.id] ?? .hidden()

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("・\(item.text)")
                                Spacer(minLength: 12)
                                Text(itemState.status.displayLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if !itemState.shortEvidence.isEmpty {
                                Text(itemState.shortEvidence)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("confidence \(Int(itemState.confidence * 100))% / 更新 \(itemState.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct CommentMaterialView: View {
    let aiMemo: String

    var body: some View {
        SectionContainer("短評素材 / AIメモ") {
            Text(aiMemo.isEmpty ? "なし" : aiMemo)
                .font(.body)
        }
    }
}

struct SectionViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TranscriptView(text: "テスト文字起こし")
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
            CommentMaterialView(aiMemo: "AIメモ")
        }
    }
}
