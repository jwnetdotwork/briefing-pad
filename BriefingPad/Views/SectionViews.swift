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

struct ObservationPointsView: View {
    let points: [String]

    var body: some View {
        SectionContainer("観察ポイント") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points, id: \.self) { point in
                    Text("- \(point)")
                }
            }
        }
    }
}

struct GoodPointsView: View {
    let points: [String]

    var body: some View {
        SectionContainer("良かった点") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points, id: \.self) { point in
                    Text("- \(point)")
                }
            }
        }
    }
}

struct CommentMaterialView: View {
    let aiMemo: String

    var body: some View {
        SectionContainer("短評素材 / AIメモ") {
            Text(aiMemo)
                .font(.body)
        }
    }
}

#Preview {
    VStack {
        TranscriptView(text: "テスト文字起こし")
        ObservationPointsView(points: ["ポイント1", "ポイント2"])
        GoodPointsView(points: ["良かった点1"])
        CommentMaterialView(aiMemo: "AIメモ")
    }
}
