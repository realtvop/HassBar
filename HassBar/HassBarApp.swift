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
        } else {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                    }
                    MenuBarSensorLabelItem(row: row)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
        }
    }
}

private struct MenuBarSensorLabelItem: View {
    let row: MenuBarSensorRow

    var body: some View {
        HStack(spacing: 3) {
            if row.item.showsIcon {
                Image(systemName: iconName)
            }
            Text(EntityMenuStyle.statusText(for: row.entity))
                .lineLimit(1)
        }
        .opacity(row.entity.isAvailable ? 1 : 0.55)
    }

    private var iconName: String {
        if !row.item.iconName.isEmpty,
           NSImage(systemSymbolName: row.item.iconName, accessibilityDescription: nil) != nil {
            return row.item.iconName
        }
        return EntityMenuStyle.systemImage(for: row.entity.domain)
    }
}
