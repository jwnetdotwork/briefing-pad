import XCTest
import Combine
@testable import BriefingPad

final class SessionPersistenceTests: XCTestCase {

    private let lastSelectedSessionKey = "lastSelectedSessionId"

    @MainActor
    func testRestoresSessionOnBootstrap() async throws {
        let userDefaults = UserDefaults(suiteName: "SessionPersistenceTests")!
        userDefaults.removePersistentDomain(forName: "SessionPersistenceTests")

        let sessionId = "persisted-session"
        userDefaults.set(sessionId, forKey: lastSelectedSessionKey)

        let mockStore = MockSessionStore()
        let session = BriefingSession(id: sessionId, name: "Persisted", parts: [])
        mockStore.savedSessions[sessionId] = SavedSession(
            sessionId: sessionId,
            templateSnapshot: session,
            updatedAt: Date(),
            partRuns: [:]
        )

        let viewModel = SessionViewModel(
            micService: MockMicrophoneService(),
            store: mockStore,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        XCTAssertEqual(viewModel.selectedSessionId, sessionId)
        XCTAssertEqual(viewModel.selectedSession?.name, "Persisted")
    }

    @MainActor
    func testFallbackWhenStoredIdIsMissing() async throws {
        let userDefaults = UserDefaults(suiteName: "SessionPersistenceTests")!
        userDefaults.removePersistentDomain(forName: "SessionPersistenceTests")

        let sessionId = "session-1"
        let mockStore = MockSessionStore()
        let session = BriefingSession(id: sessionId, name: "First", parts: [])
        mockStore.savedSessions[sessionId] = SavedSession(
            sessionId: sessionId,
            templateSnapshot: session,
            updatedAt: Date(),
            partRuns: [:]
        )

        let viewModel = SessionViewModel(
            micService: MockMicrophoneService(),
            store: mockStore,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        XCTAssertEqual(viewModel.selectedSessionId, sessionId, "Should fallback to first available session")
        XCTAssertEqual(userDefaults.string(forKey: lastSelectedSessionKey), sessionId, "Should persist the fallback session")
    }

    @MainActor
    func testFallbackWhenStoredIdIsStale() async throws {
        let userDefaults = UserDefaults(suiteName: "SessionPersistenceTests")!
        userDefaults.removePersistentDomain(forName: "SessionPersistenceTests")

        userDefaults.set("non-existent-id", forKey: lastSelectedSessionKey)

        let sessionId = "session-1"
        let mockStore = MockSessionStore()
        let session = BriefingSession(id: sessionId, name: "First", parts: [])
        mockStore.savedSessions[sessionId] = SavedSession(
            sessionId: sessionId,
            templateSnapshot: session,
            updatedAt: Date(),
            partRuns: [:]
        )

        let viewModel = SessionViewModel(
            micService: MockMicrophoneService(),
            store: mockStore,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        XCTAssertEqual(viewModel.selectedSessionId, sessionId, "Should fallback to first available session")
        XCTAssertEqual(userDefaults.string(forKey: lastSelectedSessionKey), sessionId, "Should persist the fallback session")
    }

    @MainActor
    func testChangingSessionUpdatesPersistence() async throws {
        let userDefaults = UserDefaults(suiteName: "SessionPersistenceTests")!
        userDefaults.removePersistentDomain(forName: "SessionPersistenceTests")

        let mockStore = MockSessionStore()
        let session1 = BriefingSession(id: "s1", name: "S1", parts: [])
        let session2 = BriefingSession(id: "s2", name: "S2", parts: [])

        mockStore.savedSessions["s1"] = SavedSession(sessionId: "s1", templateSnapshot: session1, updatedAt: Date(), partRuns: [:])
        mockStore.savedSessions["s2"] = SavedSession(sessionId: "s2", templateSnapshot: session2, updatedAt: Date(), partRuns: [:])

        let viewModel = SessionViewModel(
            micService: MockMicrophoneService(),
            store: mockStore,
            userDefaults: userDefaults
        )

        try await waitUntil(message: "ViewModel should be bootstrapped") {
            viewModel.isBootstrapped
        }

        viewModel.selectSession(id: "s2")
        XCTAssertEqual(userDefaults.string(forKey: lastSelectedSessionKey), "s2")

        viewModel.createEmptySession(name: "New Session")
        let newId = viewModel.selectedSessionId
        XCTAssertFalse(newId.isEmpty)
        XCTAssertNotEqual(newId, "s2")
        XCTAssertEqual(userDefaults.string(forKey: lastSelectedSessionKey), newId)
    }
}
