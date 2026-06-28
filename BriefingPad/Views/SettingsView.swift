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
            Text("settings.title")
                .font(.headline)

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading) {
                    Text("settings.openaiApiKey")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("settings.placeholder.openaiApiKey", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("settings.notionIntegrationToken")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("settings.placeholder.notionToken", text: $notionToken)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("settings.apiEndpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("settings.placeholder.apiEndpoint", text: $customEndpoint)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("settings.modelName")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("settings.placeholder.modelName", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("settings.sessionSortOrder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("settings.sessionSortOrder", selection: $sortOrder) {
                        ForEach(SessionSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            HStack {
                Button("common.cancel") {
                    dismiss()
                }

                Spacer()

                Button("common.save") {
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
        .alert("common.error", isPresented: $showError) {
            Button("common.ok") { }
        } message: {
            Text(errorMessage ?? NSLocalizedString("common.unknownError", comment: ""))
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
