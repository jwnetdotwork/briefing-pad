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
                HStack(spacing: 8) {
                    Button {
                        if selectedPartIndex > 0 {
                            onSelect(selectedPartIndex - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPartIndex <= 0)
                    .accessibilityIdentifier("PreviousPartButton")

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

                    Button {
                        if selectedPartIndex < parts.count - 1 {
                            onSelect(selectedPartIndex + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .bold))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPartIndex >= parts.count - 1)
                    .accessibilityIdentifier("NextPartButton")
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
