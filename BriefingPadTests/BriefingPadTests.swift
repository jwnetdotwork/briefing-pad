//
//  BriefingPadTests.swift
//  BriefingPadTests
//
//  Created by 山下慎平 on 2026/06/20.
//

import Foundation
import Testing
@testable import BriefingPad

@MainActor
struct BriefingPadTests {

    @Test func loadsLocalPartDefinitions() async throws {
        let bundle = Bundle(for: TestBundleToken.self)
        let sessions = LocalBriefingDataStore.loadSessions(bundle: bundle)

        #expect(sessions.count == 1)
        let partsCount = sessions[0].parts.count
        #expect(partsCount == 2)

        let lpCount = sessions[0].parts[0].learningPoints.count
        #expect(lpCount == 1)

        let status = sessions[0].parts[0].analysisState.positiveItemStates["pos-a"]?.status
        #expect(status == .strong)
    }

}

private final class TestBundleToken {}
