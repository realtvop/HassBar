//
//  MenuBarView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

struct MenuBarView: View {
    let store: HomeAssistantStore
    @Environment(\.openSettings) private var openSettings

    /// Wired in a later step to open the entity selection window.
    var onManageEntities: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 340)
        .task {
            await store.refreshIfConfigured()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            statusDot
            statusText
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(store.isLoading || !store.config.isConfigured)
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch store.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .unconfigured: return .gray
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: Text {
        switch store.status {
        case .connected: return Text("Connected")
        case .connecting: return Text("Connecting…")
        case .unconfigured: return Text("Not configured")
        case .disconnected: return Text("Disconnected")
        case .error: return Text("Connection error")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !store.config.isConfigured {
            emptyState(
                message: "Configure Home Assistant to get started.",
                actionTitle: "Open Settings",
                action: { openSettings() }
            )
        } else if store.favoriteRows.isEmpty {
            emptyState(
                message: "No favorite entities selected.",
                actionTitle: "Manage Entities",
                action: onManageEntities
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.favoriteRows) { entity in
                        FavoriteRow(entity: entity)
                        if entity.id != store.favoriteRows.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private func emptyState(message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Manage Entities…", action: onManageEntities)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Favorite row

private struct FavoriteRow: View {
    let entity: HAEntity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.systemImage(for: entity.domain))
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.friendlyName)
                    .lineLimit(1)
                Text(entity.displayState)
                    .font(.caption)
                    .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(entity.isAvailable ? 1 : 0.6)
    }

    private static func systemImage(for domain: String) -> String {
        switch HADomain(rawValue: domain) {
        case .sensor: return "gauge"
        case .binarySensor: return "sensor"
        case .light: return "lightbulb"
        case .switchDomain: return "power"
        case .cover: return "blinds"
        case .lock: return "lock"
        case .scene: return "sparkles"
        case .script: return "applescript"
        default: return "circle"
        }
    }
}