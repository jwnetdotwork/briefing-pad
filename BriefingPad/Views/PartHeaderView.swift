import SwiftUI

struct PartHeaderView: View {
    let part: PartDefinition
    @ObservedObject var viewModel: SessionViewModel
    @State private var showingEditSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: NSLocalizedString("partHeader.titleFormat", comment: ""), part.number, part.title))
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
                Text(part.durationMinutes.map {
                    String(format: NSLocalizedString("partHeader.durationFormat", comment: ""), $0)
                } ?? NSLocalizedString("common.notSet", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            if let setting = part.setting, !setting.isEmpty {
                Text(String(format: NSLocalizedString("partHeader.settingFormat", comment: ""), setting))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            let lpText = part.learningPoints.isEmpty
                ? NSLocalizedString("common.none", comment: "")
                : part.learningPoints.map { $0.text }.joined(separator: "、")
            Text(String(format: NSLocalizedString("partHeader.learningPointsFormat", comment: ""), lpText))
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
            viewModel: SessionViewModel(micService: MicrophoneService())
        )
    }
}
