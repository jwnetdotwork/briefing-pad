import SwiftUI

struct PartFormView: View {
    @Binding var numberString: String
    @Binding var title: String
    @Binding var durationString: String
    @Binding var setting: String
    @Binding var learningPointsText: String
    @Binding var observationItemsText: String
    @Binding var positiveItemsText: String

    var body: some View {
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
    }
}
