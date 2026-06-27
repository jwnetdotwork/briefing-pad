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
                Text("パート追加")
                    .font(.headline)
                Spacer()
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("番号", text: $numberString)
                    TextField("タイトル", text: $title)
                    TextField("時間（分）", text: $durationString)
                    TextField("場面設定", text: $setting)
                }

                Section("学習ポイント（1行1件）") {
                    TextEditor(text: $learningPointsText)
                        .frame(minHeight: 60)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                }

                Section("観察メモ（1行1件）") {
                    TextEditor(text: $observationItemsText)
                        .frame(minHeight: 60)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                }

                Section("良かった点候補（1行1件）") {
                    TextEditor(text: $positiveItemsText)
                        .frame(minHeight: 60)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("作成") {
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
