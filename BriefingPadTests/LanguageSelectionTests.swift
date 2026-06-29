import XCTest
@testable import BriefingPad

@MainActor
final class LanguageSelectionTests: XCTestCase {
    private let persistenceSuiteName = "test_suite"
    private let fallbackSuiteName = "test_suite_fallback"

    override func tearDown() {
        UserDefaults(suiteName: persistenceSuiteName)?.removePersistentDomain(forName: persistenceSuiteName)
        UserDefaults(suiteName: fallbackSuiteName)?.removePersistentDomain(forName: fallbackSuiteName)
        super.tearDown()
    }

    private func makeCleanUserDefaults(suiteName: String) -> UserDefaults {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

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
        let userDefaults = makeCleanUserDefaults(suiteName: persistenceSuiteName)
        let mockTranscription = MockSpeechTranscriptionService()
        let mockMic = MockMicrophoneService()
        let viewModel = SessionViewModel(
            transcriptionService: mockTranscription,
            micService: mockMic,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        // Default is dynamic based on system language.
        // Mock supports [ja-JP, en-US], so it should be one of those.
        XCTAssertTrue(["ja-JP", "en-US"].contains(viewModel.selectedTranscriptionLocale))
        let initialLocale = viewModel.selectedTranscriptionLocale

        // Update locale
        viewModel.updateTranscriptionLocale("en-US")
        XCTAssertEqual(viewModel.selectedTranscriptionLocale, "en-US")
        XCTAssertEqual(userDefaults.string(forKey: SessionViewModel.selectedLocaleKey), "en-US")

        // Create new ViewModel with same UserDefaults
        let viewModel2 = SessionViewModel(
            transcriptionService: mockTranscription,
            micService: mockMic,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel 2 should be bootstrapped") {
            viewModel2.isBootstrapped
        }

        XCTAssertEqual(viewModel2.selectedTranscriptionLocale, "en-US")
    }

    func testSessionViewModelLocaleFallback() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: fallbackSuiteName)

        // Save an "unsupported" locale
        userDefaults.set("fr-FR", forKey: SessionViewModel.selectedLocaleKey)

        let mockTranscription = MockSpeechTranscriptionService() // Supports ja-JP and en-US
        let mockMic = MockMicrophoneService()
        let viewModel = SessionViewModel(
            transcriptionService: mockTranscription,
            micService: mockMic,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        // fr-FR is not in mock's [ja-JP, en-US], so it should fallback to ja-JP
        XCTAssertEqual(viewModel.selectedTranscriptionLocale, "ja-JP")

        // Should be saved immediately to UserDefaults
        XCTAssertEqual(userDefaults.string(forKey: SessionViewModel.selectedLocaleKey), "ja-JP")
    }

    func testInitialLocaleResolution_ExactMatch() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: "test_exact")
        let viewModel = SessionViewModel(micService: MockMicrophoneService(), userDefaults: userDefaults)

        let supported = [Locale(identifier: "ja-JP"), Locale(identifier: "en-US")]
        let preferred = ["en-US", "ja-JP"]

        let result = viewModel.resolveInitialLocale(supportedLocales: supported, preferredIdentifiers: preferred)
        XCTAssertEqual(result, "en-US")
    }

    func testInitialLocaleResolution_LanguageCodeMatch() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: "test_lang")
        let viewModel = SessionViewModel(micService: MockMicrophoneService(), userDefaults: userDefaults)

        let supported = [Locale(identifier: "en-GB"), Locale(identifier: "ja-JP")]
        let preferred = ["en-US"] // en match en-GB

        let result = viewModel.resolveInitialLocale(supportedLocales: supported, preferredIdentifiers: preferred)
        XCTAssertEqual(result, "en-GB")
    }

    func testInitialLocaleResolution_FallbackToJaJP() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: "test_ja_fallback")
        let viewModel = SessionViewModel(micService: MockMicrophoneService(), userDefaults: userDefaults)

        let supported = [Locale(identifier: "ja-JP"), Locale(identifier: "en-US")]
        let preferred = ["fr-FR"] // No match

        let result = viewModel.resolveInitialLocale(supportedLocales: supported, preferredIdentifiers: preferred)
        XCTAssertEqual(result, "ja-JP")
    }

    func testInitialLocaleResolution_FallbackToFirst() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: "test_first_fallback")
        let viewModel = SessionViewModel(micService: MockMicrophoneService(), userDefaults: userDefaults)

        let supported = [Locale(identifier: "fr-FR"), Locale(identifier: "de-DE")]
        let preferred = ["en-US"] // No match, no ja-JP

        let result = viewModel.resolveInitialLocale(supportedLocales: supported, preferredIdentifiers: preferred)
        XCTAssertEqual(result, "fr-FR")
    }

    func testInitialLocaleNoSaveToUserDefaults() async throws {
        let userDefaults = makeCleanUserDefaults(suiteName: "test_no_save")
        let mockTranscription = MockSpeechTranscriptionService()
        mockTranscription.supportedLocales = [Locale(identifier: "en-US")]

        // We can't mock Locale.preferredLanguages, but we can verify that whatever it picks, it DOES NOT save it.
        let viewModel = SessionViewModel(
            transcriptionService: mockTranscription,
            micService: MockMicrophoneService(),
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        XCTAssertFalse(userDefaults.object(forKey: SessionViewModel.selectedLocaleKey) != nil)
    }
}
