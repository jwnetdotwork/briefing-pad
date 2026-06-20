import SwiftUI

struct SessionToolbarView: View {
    @Binding var selectedSessionId: UUID?
    let sessions: [Session]

    var body: some View {
        HStack {
            Picker("セッション選択", selection: $selectedSessionId) {
                ForEach(sessions) { session in
                    Text(session.name).tag(session.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)

            Button(action: {}) {
                Image(systemName: "plus")
            }
            .help("新規追加")

            Button(action: {}) {
                Image(systemName: "trash")
            }
            .help("削除")

            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    SessionToolbarView(
        selectedSessionId: .constant(Session.dummySessions[0].id),
        sessions: Session.dummySessions
    )
}
