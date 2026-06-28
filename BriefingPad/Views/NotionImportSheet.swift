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
            Text("notionImport.title")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("notionImport.pageUrlOrId")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("notionImport.placeholder.pageUrl", text: $notionURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
                    .onChange(of: notionURL) {
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
                Button("common.cancel") {
                    dismiss()
                }
                .disabled(isLoading)

                Spacer()

                if preview == nil {
                    Button("notionImport.preview") {
                        generatePreview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || notionURL.isEmpty)
                } else {
                    Button("notionImport.import") {
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

            Text(String(format: NSLocalizedString("notionImport.sessionNameFormat", comment: ""), preview.sessionName))
                .font(.subheadline.bold())

            Text("notionImport.partsHeading")
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
                                    Label(String(format: NSLocalizedString("notionImport.minutesFormat", comment: ""), minutes), systemImage: "clock")
                                }
                                if let setting = part.setting {
                                    Label(setting, systemImage: "mappin.and.ellipse")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                            HStack(spacing: 15) {
                                previewStat(label: NSLocalizedString("notionImport.stat.learning", comment: ""), count: part.learningPointCount)
                                previewStat(label: NSLocalizedString("notionImport.stat.observation", comment: ""), count: part.observationItemCount)
                                previewStat(label: NSLocalizedString("notionImport.stat.positive", comment: ""), count: part.positiveItemCount)
                                if part.hasAIMemo {
                                    Text("notionImport.aiMemoBadge")
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
                Text(String(format: NSLocalizedString("notionImport.uninterpretedBlockCountFormat", comment: ""), preview.uninterpretedBlockCount))
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
            errorMessage = NSLocalizedString("notionImport.error.saveToken", comment: "")
            return
        }

        guard let id = NotionClient.normalizePageId(notionURL) else {
            errorMessage = NSLocalizedString("notionImport.error.invalidURL", comment: "")
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
                    self.errorMessage = NSLocalizedString("notionImport.error.authenticationFailed", comment: "")
                    self.isLoading = false
                }
            } catch NotionError.permissionDenied {
                await MainActor.run {
                    self.errorMessage = NSLocalizedString("notionImport.error.permissionDenied", comment: "")
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(
                        format: NSLocalizedString("notionImport.error.fetchFailedFormat", comment: ""),
                        error.localizedDescription
                    )
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
                    self.errorMessage = String(
                        format: NSLocalizedString("notionImport.error.importFailedFormat", comment: ""),
                        error.localizedDescription
                    )
                    self.isLoading = false
                }
            }
        }
    }
}
