import SwiftUI

struct SessionToolbarView: View {
    @Binding var selectedSessionId: String
    let sessions: [BriefingSession]
    let keychainService: KeychainServiceProtocol
    @State private var showingSettings = false

    var body: some View {
        HStack {
            Picker("セッション選択", selection: $selectedSessionId) {
                ForEach(sessions) { session in
                    Text(session.name).tag(session.id)
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

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help("設定")
            .sheet(isPresented: $showingSettings) {
                SettingsView(keychainService: keychainService)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SessionToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        SessionToolbarView(
            selectedSessionId: .constant(LocalBriefingDataStore.fallbackSessions[0].id),
            sessions: LocalBriefingDataStore.fallbackSessions,
            keychainService: MockKeychainService()
        )
    }
}
