//
//  MenuBarView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("HassBar")
        Button("Settings…") { openSettings() }
        Divider()
        Button("Quit HassBar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}