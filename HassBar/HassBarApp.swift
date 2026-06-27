//
//  HassBarApp.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

@main
struct HassBarApp: App {
    @State private var store = HomeAssistantStore(config: AppConfig())

    var body: some Scene {
        MenuBarExtra("HassBar", systemImage: "house.fill") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}