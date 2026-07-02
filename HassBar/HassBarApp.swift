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
    @State private var settingsTab: SettingsTab = .connection

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, settingsTab: $settingsTab)
        } label: {
            MenuBarStatusLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, selectedTab: $settingsTab)
        }
    }
}

private struct MenuBarStatusLabel: View {
    let store: HomeAssistantStore

    var body: some View {
        let rows = store.menuBarSensorRows
        if rows.isEmpty {
            Label("HassBar", systemImage: "house.fill")
        } else if store.showsAppIconInMenuBar {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                menuBarText(for: rows)
            }
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
        } else {
            menuBarText(for: rows)
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
        }
    }

    private func menuBarText(for rows: [MenuBarSensorRow]) -> Text {
        rows.enumerated().reduce(Text("")) { partial, item in
            let separator = item.offset == 0 ? Text("") : Text(" · ")
            return partial + separator + menuBarText(for: item.element)
        }
    }

    private func menuBarText(for row: MenuBarSensorRow) -> Text {
        let status = Text(EntityMenuStyle.statusText(for: row.entity))

        if row.item.showsIcon {
            return Text(Image(systemName: iconName(for: row))) + Text(" ") + status
        }

        return status
    }

    private func iconName(for row: MenuBarSensorRow) -> String {
        if !row.item.iconName.isEmpty,
           NSImage(systemSymbolName: row.item.iconName, accessibilityDescription: nil) != nil {
            return row.item.iconName
        }
        return EntityMenuStyle.systemImage(for: row.entity.domain)
    }
}
