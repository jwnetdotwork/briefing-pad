import SwiftUI

struct PartHeaderView: View {
    let part: Part

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(part.title)
                .font(.headline)
            Text("持ち時間: \(part.durationMinutes)分")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    PartHeaderView(part: Session.dummySessions[0].parts[1])
}
