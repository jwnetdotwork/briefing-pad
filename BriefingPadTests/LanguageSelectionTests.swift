import XCTest
@testable import BriefingPad

@MainActor
final class LanguageSelectionTests: XCTestCase {

    func testLocaleDiscoveryAndSorting() async {
        let service = SpeechTranscriptionService()
        let locales = await service.getSupportedLocales()

        // Since we can't easily mock SpeechTranscriber.supportedLocale in this environment,
        // we at least check that it doesn't crash and returns a sorted list if not empty.
        if !locales.isEmpty {
            for i in 0..<locales.count - 1 {
                let nameA = Locale.current.localizedString(forIdentifier: locales[i].identifier) ?? locales[i].identifier
                let nameB = Locale.current.localizedString(forIdentifier: locales[i+1].identifier) ?? locales[i+1].identifier
                XCTAssertTrue(nameA.localizedCompare(nameB) != .orderedDescending)
            }

            // Check deduplication (identifiers should be unique)
            let identifiers = locales.map { $0.identifier }
            XCTAssertEqual(identifiers.count, Set(identifiers).count)
        }
    }

    func testSessionViewModelLocalePersistence() async throws {
        let userDefaults = UserDefaults(suiteName: "test_suite")!
        userDefaults.removePersistentDomain(forName: "test_suite")

        let mockTranscription = MockSpeechTranscriptionService()
        let viewModel = SessionViewModel(
            transcriptionService: mockTranscription,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        // Default should be ja-JP
        XCTAssertEqual(viewModel.selectedTranscriptionLocale, "ja-JP")

        // Update locale
        viewModel.updateTranscriptionLocale("en-US")
        XCTAssertEqual(viewModel.selectedTranscriptionLocale, "en-US")
        XCTAssertEqual(userDefaults.string(forKey: SessionViewModel.selectedLocaleKey), "en-US")

        // Create new ViewModel with same UserDefaults
        let viewModel2 = SessionViewModel(
            transcriptionService: mockTranscription,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel 2 should be bootstrapped") {
            viewModel2.isBootstrapped
        }

        XCTAssertEqual(viewModel2.selectedTranscriptionLocale, "en-US")
    }

    func testSessionViewModelLocaleFallback() async throws {
        let userDefaults = UserDefaults(suiteName: "test_suite_fallback")!
        userDefaults.removePersistentDomain(forName: "test_suite_fallback")

        // Save an "unsupported" locale
        userDefaults.set("fr-FR", forKey: "selectedTranscriptionLocale")

        let mockTranscription = MockSpeechTranscriptionService() // Supports ja-JP and en-US
        let viewModel = SessionViewModel(
            transcriptionService: mockTranscription,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        // fr-FR is not in mock's [ja-JP, en-US], so it should fallback to ja-JP
        XCTAssertEqual(viewModel.selectedTranscriptionLocale, "ja-JP")
    }
}
