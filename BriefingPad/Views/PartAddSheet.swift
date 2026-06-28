import SwiftUI

struct PartAddSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) var dismiss

    @State private var numberString: String = ""
    @State private var title: String = ""
    @State private var durationString: String = ""
    @State private var setting: String = ""
    @State private var learningPointsText: String = ""
    @State private var observationItemsText: String = ""
    @State private var positiveItemsText: String = ""

    init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
        // Suggested next number
        let nextNumber = (viewModel.selectedSession?.parts.map { $0.number }.max() ?? 0) + 1
        _numberString = State(initialValue: String(nextNumber))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("partAddSheet.title")
                    .font(.headline)
                Spacer()
                Button("common.cancel") {
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
                Button("common.create") {
                    let number = Int(numberString)
                    let duration = Int(durationString)

                    viewModel.addManualPart(
                        number: number,
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
