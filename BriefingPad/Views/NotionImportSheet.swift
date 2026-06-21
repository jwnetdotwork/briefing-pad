import SwiftUI

struct NotionImportSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SessionViewModel
    let keychainService: KeychainServiceProtocol
    let importService: NotionImportServiceProtocol

    @State private var notionURL: String = ""
    @State private var preview: NotionPreview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var pageId: String?

    init(viewModel: SessionViewModel, keychainService: KeychainServiceProtocol, importService: NotionImportServiceProtocol = NotionImportService()) {
        self.viewModel = viewModel
        self.keychainService = keychainService
        self.importService = importService
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Notion からインポート")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notion ページ URL または ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://app.notion.com/...", text: $notionURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
                    .onChange(of: notionURL) { _ in
                        preview = nil
                        pageId = nil
                    }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let preview = preview {
                previewSection(preview)
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .disabled(isLoading)

                Spacer()

                if preview == nil {
                    Button("プレビュー確認") {
                        generatePreview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || notionURL.isEmpty)
                } else {
                    Button("インポート確定") {
                        performImport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            }

            if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .padding()
        .frame(minWidth: 500, maxWidth: 500, minHeight: 400)
    }

    @ViewBuilder
    private func previewSection(_ preview: NotionPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("セッション名: \(preview.sessionName)")
                .font(.subheadline.bold())

            Text("インポート対象パート:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(preview.parts, id: \.title) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.title)
                                .font(.system(size: 13, weight: .medium))

                            HStack(spacing: 12) {
                                if let minutes = part.durationMinutes {
                                    Label("\(minutes)分", systemImage: "clock")
                                }
                                if let setting = part.setting {
                                    Label(setting, systemImage: "mappin.and.ellipse")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                            HStack(spacing: 15) {
                                previewStat(label: "学習", count: part.learningPointCount)
                                previewStat(label: "観察", count: part.observationItemCount)
                                previewStat(label: "良点", count: part.positiveItemCount)
                                if part.hasAIMemo {
                                    Text("🤖AIメモ有")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 200)

            HStack {
                Text("未解釈ブロック数: \(preview.uninterpretedBlockCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func previewStat(label: String, count: Int) -> some View {
        Text("\(label): \(count)")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    private func generatePreview() {
        guard let token = keychainService.load(key: KeychainKeys.notionIntegrationToken), !token.isEmpty else {
            errorMessage = "設定画面で Notion トークンを保存してください"
            return
        }

        guard let id = NotionClient.normalizePageId(notionURL) else {
            errorMessage = "URL が不正です"
            return
        }

        self.pageId = id
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await importService.testConnection(token: token, pageId: id)
                let previewResult = try await importService.generatePreview(token: token, pageId: id)
                await MainActor.run {
                    self.preview = previewResult
                    self.isLoading = false
                }
            } catch NotionError.authenticationFailed {
                await MainActor.run {
                    self.errorMessage = "認証失敗（トークンを確認してください）"
                    self.isLoading = false
                }
            } catch NotionError.permissionDenied {
                await MainActor.run {
                    self.errorMessage = "共有不足（インテグレーションをページに招待してください）"
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "取得失敗: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func performImport() {
        guard let token = keychainService.load(key: KeychainKeys.notionIntegrationToken), let id = pageId else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let session = try await importService.importSession(token: token, pageId: id)
                await MainActor.run {
                    viewModel.importNotionSession(session, notionPageId: id)
                    self.isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "インポート失敗: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
