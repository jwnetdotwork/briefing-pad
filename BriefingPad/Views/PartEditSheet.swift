import SwiftUI

struct PartEditSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    let part: PartDefinition
    @Environment(\.dismiss) var dismiss

    @State private var numberString: String = ""
    @State private var title: String = ""
    @State private var durationString: String = ""
    @State private var setting: String = ""
    @State private var learningPointsText: String = ""
    @State private var observationItemsText: String = ""
    @State private var positiveItemsText: String = ""

    init(viewModel: SessionViewModel, part: PartDefinition) {
        self.viewModel = viewModel
        self.part = part
        _numberString = State(initialValue: String(part.number))
        _title = State(initialValue: part.title)
        _durationString = State(initialValue: part.durationMinutes.map { String($0) } ?? "")
        _setting = State(initialValue: part.setting ?? "")
        _learningPointsText = State(initialValue: part.learningPoints.map { $0.text }.joined(separator: "\n"))
        _observationItemsText = State(initialValue: part.observationItems.map { $0.text }.joined(separator: "\n"))
        _positiveItemsText = State(initialValue: part.positiveItems.map { $0.text }.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("パート編集")
                    .font(.headline)
                Spacer()
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            PartFormView(
                numberString: $numberString,
                title: $title,
                durationString: $durationString,
                setting: $setting,
                learningPointsText: $learningPointsText,
                observationItemsText: $observationItemsText,
                positiveItemsText: $positiveItemsText
            )

            Divider()

            HStack {
                Spacer()
                Button("保存") {
                    let number = Int(numberString)
                    let duration = Int(durationString)

                    viewModel.updatePart(
                        id: part.id,
                        number: number ?? part.number,
                        title: title,
                        durationMinutes: duration,
                        setting: setting.isEmpty ? nil : setting,
                        learningPointsText: learningPointsText,
                        observationItemsText: observationItemsText,
                        positiveItemsText: positiveItemsText
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.micStatus == .recording || viewModel.micStatus == .starting)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
}
