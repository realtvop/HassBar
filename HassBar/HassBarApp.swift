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
                Label {
                    Text("HassBar")
                } icon: {
                    appIcon
                }
                .labelStyle(.titleAndIcon)
            } else if store.showsAppIconInMenuBar {
                Label {
                    menuBarText(for: rows)
                } icon: {
                    appIcon
                }
                .labelStyle(.titleAndIcon)
            } else {
                menuBarText(for: rows)
            }
        }
        .font(Self.labelFont)
        .lineLimit(1)
        .frame(maxWidth: 260, alignment: .leading)
        .task {
            await store.refreshIfConfigured()
        }
    }

    private var appIcon: some View {
        Image(systemName: "house.fill")
            .font(Self.iconFont)
            .offset(y: Self.iconVerticalOffset)
    }

    private func menuBarText(for rows: [MenuBarSensorRow]) -> Text {
        rows.enumerated().reduce(Text("")) { partial, item in
            let separator = item.offset == 0 ? Text(" ") : Self.separatorText
            return partial + separator + menuBarText(for: item.element)
        }
    }

    private func menuBarText(for row: MenuBarSensorRow) -> Text {
        let status = Text(EntityMenuStyle.statusText(for: row.entity))
        let content: Text

        if row.item.showsIcon {
            content = iconText(named: iconName(for: row)) + Self.separatorText + status
        } else {
            content = status
        }

        if row.entity.isAvailable {
            return content
        }

        return content.foregroundColor(.secondary)
    }

    private func iconText(named iconName: String) -> Text {
        Text(Image(systemName: iconName))
            .font(Self.iconTextFont)
            .baselineOffset(Self.iconBaselineOffset)
    }

    private static let labelFont = Font.system(size: 4, weight: .regular)
    private static let iconFont = Font.system(size: 10, weight: .regular)
    private static let iconTextFont = Font.system(size: 9.5, weight: .regular)
    private static let iconVerticalOffset: CGFloat = -1.5
    private static let iconBaselineOffset: CGFloat = 1.75
    private static let separatorText = Text("  ")

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
