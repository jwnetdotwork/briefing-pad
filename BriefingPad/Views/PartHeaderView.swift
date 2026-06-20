import SwiftUI

struct PartHeaderView: View {
    let part: PartDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Part \(part.number). \(part.title)")
                .font(.headline)
            Text("持ち時間: \(part.durationMinutes.map { "\($0)分" } ?? "未設定")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let setting = part.setting, !setting.isEmpty {
                Text("場面設定: \(setting)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct PartHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        PartHeaderView(part: LocalBriefingDataStore.fallbackSessions[0].parts[1])
    }
}
