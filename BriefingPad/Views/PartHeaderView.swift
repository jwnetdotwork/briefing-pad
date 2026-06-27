import SwiftUI

struct PartHeaderView: View {
    let part: PartDefinition
    @ObservedObject var viewModel: SessionViewModel
    @State private var showingEditSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Part \(part.number). \(part.title)")
                    .font(.headline)

                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.micStatus == .recording || viewModel.micStatus == .starting)
                .sheet(isPresented: $showingEditSheet) {
                    PartEditSheet(viewModel: viewModel, part: part)
                }

                Spacer()
                Text(part.durationMinutes.map { "\($0)分" } ?? "未設定")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            if let setting = part.setting, !setting.isEmpty {
                Text("場面設定: \(setting)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            let lpText = part.learningPoints.isEmpty
                ? "なし"
                : part.learningPoints.map { $0.text }.joined(separator: "、")
            Text("学習ポイント: \(lpText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct PartHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        PartHeaderView(
            part: LocalBriefingDataStore.fallbackSessions[0].parts[1],
            viewModel: SessionViewModel()
        )
    }
}
