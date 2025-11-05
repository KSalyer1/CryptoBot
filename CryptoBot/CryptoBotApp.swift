//
//  CryptoBotApp.swift
//  CryptoBot
//
//  Created by Keith  Salyer on 10/7/25.
//

import SwiftUI

@main
struct CryptoBotApp: App {
    @State private var appState = ApplicationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
