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
                TextField("part.number", text: $numberString)
                TextField("part.title", text: $title)
                TextField("part.duration", text: $durationString)
                TextField("part.setting", text: $setting)
            }

            Section("part.learningpoints") {
                TextEditor(text: $learningPointsText)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
            }

            Section("part.observationitems") {
                TextEditor(text: $observationItemsText)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
            }

            Section("part.positiveitems") {
                TextEditor(text: $positiveItemsText)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
            }
        }
        .formStyle(.grouped)
    }
}
