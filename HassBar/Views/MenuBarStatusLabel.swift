import SwiftUI

struct MenuBarStatusLabel: View {
    let store: HomeAssistantStore

    var body: some View {
        Group {
            let rows = store.menuBarSensorRows
            if rows.isEmpty {
                appIcon
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
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityLabel(accessibilitySummary)
        .help(accessibilitySummary)
        .frame(maxWidth: 260, alignment: .leading)
        .task {
            await store.refreshIfConfigured()
        }
    }

    private var accessibilitySummary: String {
        let values = store.menuBarSensorRows.map {
            "\(store.displayName(for: $0.entity)): \(EntityMenuStyle.statusText(for: $0.entity))"
        }
        return (["HassBar"] + values).joined(separator: ", ")
    }

    private var appIcon: some View {
        Image(systemName: "house.fill")
            .font(Self.iconFont)
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
    }

    private static let labelFont = Font.system(size: 11, weight: .regular)
    private static let iconFont = Font.system(size: 11, weight: .regular)
    private static let iconTextFont = Font.system(size: 11, weight: .regular)
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
