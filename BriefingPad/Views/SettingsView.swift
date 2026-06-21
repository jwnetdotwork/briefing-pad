import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""
    @State private var notionToken: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("設定")
                .font(.headline)

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading) {
                    Text("OpenAI API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Notion インテグレーション・トークン")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("secret_...", text: $notionToken)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }

                Spacer()

                Button("保存") {
                    do {
                        try keychainService.save(key: "openai_api_key", value: apiKey)
                        try keychainService.save(key: "notion_integration_token", value: notionToken)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .alert("エラー", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "不明なエラーが発生しました")
        }
        .onAppear {
            apiKey = keychainService.load(key: "openai_api_key") ?? ""
            notionToken = keychainService.load(key: "notion_integration_token") ?? ""
        }
    }
}
