//
//  BriefingPadTests.swift
//  BriefingPadTests
//
//  Created by 山下慎平 on 2026/06/20.
//

import Foundation
import Testing
@testable import BriefingPad

struct BriefingPadTests {

    @Test func loadsLocalPartDefinitions() throws {
        let bundle = Bundle(for: TestBundleToken.self)
        let sessions = LocalBriefingDataStore.loadSessions(bundle: bundle)

        #expect(sessions.count == 1)
        #expect(sessions[0].parts.count == 2)
        #expect(sessions[0].parts[0].learningPoints.count == 1)
        let status = sessions[0].parts[0].analysisState.positiveItemStates["pos-a"]?.status
        #expect(status == .strong)
    }

}

private final class TestBundleToken {}
