import SwiftUI

struct PartListView: View {
    let parts: [PartDefinition]
    let selectedPartIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        SectionContainer("パート一覧") {
            if parts.isEmpty {
                Text("パートがありません")
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(parts.indices, id: \.self) { index in
                            let part = parts[index]

                            Button {
                                onSelect(index)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Part \(part.number)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(part.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            index == selectedPartIndex
                                            ? Color.accentColor.opacity(0.15)
                                            : Color(NSColor.controlBackgroundColor)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            index == selectedPartIndex
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct PartListView_Previews: PreviewProvider {
    static var previews: some View {
        PartListView(
            parts: LocalBriefingDataStore.fallbackSessions[0].parts,
            selectedPartIndex: 1,
            onSelect: { _ in }
        )
    }
}
