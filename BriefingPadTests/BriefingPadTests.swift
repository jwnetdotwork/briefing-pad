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
        guard let session = sessions.first else {
            return
        }

        let partsCount = session.parts.count
        #expect(partsCount == 2)

        guard let part = session.parts.first else {
            return
        }

        let lpCount = part.learningPoints.count
        #expect(lpCount == 1)

        let status = part.analysisState.positiveItemStates["pos-a"]?.status
        #expect(status == .strong)
    }

}

private final class TestBundleToken {}
