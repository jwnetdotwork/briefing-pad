import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SessionViewModel
    @State private var apiKey: String = ""
    @State private var notionToken: String = ""
    @State private var customEndpoint: String = ""
    @State private var customModel: String = ""
    @State private var sortOrder: SessionSortOrder = .createdDesc
    @State private var errorMessage: String?
    @State private var showError = false
    private let keychainService: KeychainServiceProtocol

    init(viewModel: SessionViewModel, keychainService: KeychainServiceProtocol = KeychainService()) {
        self.viewModel = viewModel
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

                VStack(alignment: .leading) {
                    Text("APIエンドポイント (任意)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://api.openai.com/v1", text: $customEndpoint)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("モデル名 (任意)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("gpt-5.4-mini-2026-03-17", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("セッション表示順")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("セッション表示順", selection: $sortOrder) {
                        ForEach(SessionSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }

                Spacer()

                Button("保存") {
                    do {
                        try keychainService.save(key: KeychainKeys.openaiApiKey, value: apiKey)
                        try keychainService.save(key: KeychainKeys.notionIntegrationToken, value: notionToken)
                        UserDefaults.standard.set(customEndpoint, forKey: "customApiEndpoint")
                        UserDefaults.standard.set(customModel, forKey: "customModelName")
                        UserDefaults.standard.set(sortOrder.rawValue, forKey: "sessionSortOrder")
                        viewModel.sortOrder = sortOrder
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
            apiKey = keychainService.load(key: KeychainKeys.openaiApiKey) ?? ""
            notionToken = keychainService.load(key: KeychainKeys.notionIntegrationToken) ?? ""
            customEndpoint = UserDefaults.standard.string(forKey: "customApiEndpoint") ?? ""
            customModel = UserDefaults.standard.string(forKey: "customModelName") ?? ""
            sortOrder = viewModel.sortOrder
        }
    }
}
