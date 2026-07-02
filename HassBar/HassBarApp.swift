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
        Group {
            let rows = store.menuBarSensorRows
            if rows.isEmpty {
                HStack(alignment: .center, spacing: Self.itemSpacing) {
                    statusIcon(named: "house.fill")
                    Text("HassBar")
                }
            } else {
                HStack(alignment: .center, spacing: Self.itemSpacing) {
                    if store.showsAppIconInMenuBar {
                        statusIcon(named: "house.fill")
                    }
                    ForEach(rows) { row in
                        sensorSegment(for: row)
                    }
                }
            }
        }
        .font(Self.labelFont)
        .lineLimit(1)
        .frame(maxWidth: 260, alignment: .leading)
        .task {
            await store.refreshIfConfigured()
        }
    }

    private func sensorSegment(for row: MenuBarSensorRow) -> some View {
        HStack(alignment: .center, spacing: Self.itemSpacing) {
            if row.item.showsIcon {
                statusIcon(named: iconName(for: row))
            }
            Text(EntityMenuStyle.statusText(for: row.entity))
        }
        .lineLimit(1)
        .opacity(row.entity.isAvailable ? 1 : 0.62)
    }

    private func statusIcon(named iconName: String) -> some View {
        Image(systemName: iconName)
            .font(Self.iconFont)
            .frame(width: Self.iconFrame, height: Self.iconFrame, alignment: .center)
            .offset(y: Self.iconVerticalOffset)
    }

    private static let labelFont = Font.system(size: 12, weight: .regular)
    private static let iconFont = Font.system(size: 11, weight: .regular)
    private static let iconFrame: CGFloat = 12
    private static let iconVerticalOffset: CGFloat = -0.75
    private static let itemSpacing: CGFloat = 3

    private func iconName(for row: MenuBarSensorRow) -> String {
        if row.item.showsIcon {
            if !row.item.iconName.isEmpty,
               NSImage(systemSymbolName: row.item.iconName, accessibilityDescription: nil) != nil {
                return row.item.iconName
            }
        }
        return EntityMenuStyle.systemImage(for: row.entity.domain)
    }
}
