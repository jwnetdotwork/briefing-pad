import SwiftUI

struct SectionContainer<Content: View, Trailing: View>: View {
    let title: String
    let identifier: String?
    let content: Content
    let trailing: Trailing

    init(
        _ title: String,
        identifier: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.identifier = identifier
        self.trailing = trailing()
        self.content = content()
    }

    init(
        _ title: String,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) where Trailing == EmptyView {
        self.init(title, identifier: identifier, trailing: { EmptyView() }, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier(identifier ?? "")

                Spacer()

                trailing
            }

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
        SectionContainer(
            "文字起こし",
            identifier: "TranscriptSection",
            trailing: {
                if !segments.isEmpty {
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("クリップボードにコピー")
                }
            }
        ) {
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

    private func copyToClipboard() {
        let text = segments.map { $0.text }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct LearningPointsView: View {
    let points: [LearningPoint]

    var body: some View {
        SectionContainer("学習ポイント", identifier: "LearningPointsSection") {
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
        SectionContainer("観察メモ", identifier: "ObservationSection") {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        let itemState = state[item.id] ?? .hidden()
                        let isStrong = itemState.status == .strong
                        let isCandidate = itemState.status == .candidate

                        HStack(alignment: .firstTextBaseline) {
                            let evidence = itemState.shortEvidence.isEmpty ? "" : itemState.shortEvidence
                            let isHidden = itemState.status == .hidden
                            Text("・\(item.text)\(evidence)")
                                .foregroundColor((isStrong || isCandidate) ? .primary : .secondary)
                                .opacity(isHidden ? 0.6 : 1.0)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            if isStrong || isCandidate {
                                Text(itemState.status.displayLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize()
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

    var body: some View {
        SectionContainer("良かった点候補", identifier: "PositiveCandidatesSection") {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("なし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(displayItems, id: \.item.id) { pair in
                        let isHidden = pair.state.status == .hidden
                        let isStrong = pair.state.status == .strong
                        let isCandidate = pair.state.status == .candidate

                        HStack(alignment: .firstTextBaseline) {
                            let evidence = pair.state.shortEvidence.isEmpty ? "" : pair.state.shortEvidence
                            Text("・\(pair.item.text)\(evidence)")
                                .font(.body.bold())
                                .foregroundColor((isStrong || isCandidate) ? .primary : .secondary)
                                .opacity(isHidden ? 0.6 : 1.0)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            if isStrong || isCandidate {
                                Text(pair.state.status.displayLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayItems: [(item: PositiveItem, state: AnalysisItemState)] {
        items.map { item in
            let itemState = state[item.id] ?? .hidden()
            return (item: item, state: itemState)
        }
        .sorted {
            if $0.state.status != $1.state.status {
                return $0.state.status > $1.state.status
            }
            return $0.state.confidence > $1.state.confidence
        }
    }
}

struct CommentMaterialView: View {
    let aiMemo: String
    let generationError: String?
    let isFinalizing: Bool
    let isGenerating: Bool
    let syncStatus: SessionViewModel.NotionSyncStatus
    let onRetry: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        SectionContainer(
            "🤖 AIメモ",
            identifier: "AIMemoSection",
            trailing: {
                HStack(alignment: .center, spacing: 8) {
                    if isFinalizing || isGenerating {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isFinalizing ? "確定メモ生成中..." : "メモ生成中...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !isFinalizing && !isGenerating {
                        Button(action: onRegenerate) {
                            Label("再生成", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }

                    syncStatusView
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let error = generationError, aiMemo.isEmpty, !isFinalizing, !isGenerating {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text("メモ生成失敗: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Button("再試行", action: onRetry)
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                } else {
                    if aiMemo.isEmpty && !isFinalizing && !isGenerating {
                        Text("（パート終了後または手動実行で生成されます）")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    } else {
                        Text(aiMemo)
                            .font(.body)
                            .lineSpacing(4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        HStack(spacing: 4) {
            switch syncStatus {
            case .idle:
                EmptyView()
            case .writing:
                ProgressView()
                    .controlSize(.small)
                Text("Notion更新中...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Notion同期済み")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .externalModification:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("外部編集を検知 (追記しました)")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Button("再試行", action: onRetry)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            case .failure(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Notion同期失敗: \(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
                Button("再試行", action: onRetry)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            case .noToken:
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Notion未設定")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SectionViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TranscriptView(
                segments: [
                    TranscriptSegment(
                        sessionId: "preview-session",
                        partId: "preview-part-1",
                        text: "確定したテキスト",
                        isFinal: true,
                        startTime: 0.0,
                        endTime: 3.0
                    ),
                    TranscriptSegment(
                        sessionId: "preview-session",
                        partId: "preview-part-1",
                        text: "未確定のテキスト",
                        isFinal: false,
                        startTime: 3.0,
                        endTime: 5.0
                    )
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
            CommentMaterialView(
                aiMemo: "AIメモ",
                generationError: nil,
                isFinalizing: false,
                isGenerating: false,
                syncStatus: .success,
                onRetry: {},
                onRegenerate: {}
            )
        }
    }
}
