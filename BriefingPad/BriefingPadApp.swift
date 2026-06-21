//
//  BriefingPadApp.swift
//  BriefingPad
//
//  Created by 山下慎平 on 2026/06/20.
//

import SwiftUI

@main
struct BriefingPadApp: App {
    private let keychainService = KeychainService()

    var body: some Scene {
        WindowGroup {
            ContentView(keychainService: keychainService)
        }
    }
}
