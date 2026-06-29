//
//  MenuBarView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

struct MenuBarView: View {
    let store: HomeAssistantStore
    @Binding var settingsTab: SettingsTab
    @Environment(\.openSettings) private var openSettings

    @State private var expandedEntityID: String? = nil

    private func manageEntities() {
        settingsTab = .entities
        openSettings()
    }

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
            realtimeDot
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

    private var realtimeDot: some View {
        Group {
            if let help = realtimeHelp {
                Circle()
                    .fill(realtimeColor)
                    .frame(width: 7, height: 7)
                    .help(help)
            }
        }
    }

    private var realtimeColor: Color {
        switch store.realtimeStatus {
        case .connected: return .green
        case .connecting, .authenticating, .subscribing: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    private var realtimeHelp: String? {
        switch store.realtimeStatus {
        case .connected: return "Realtime connected"
        case .connecting: return "Realtime connecting…"
        case .authenticating: return "Authenticating…"
        case .subscribing: return "Subscribing to events…"
        case .disconnected: return "Realtime disconnected"
        case .failed(let message): return "Realtime: \(message)"
        }
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
                action: manageEntities
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.favoriteRows) { entity in
                        FavoriteRow(
                            entity: entity,
                            store: store,
                            isExpanded: expandedEntityID == entity.id,
                            expand: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedEntityID = (expandedEntityID == entity.id ? nil : entity.id)
                                }
                            }
                        )
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
            Button("Manage Entities…", action: manageEntities)
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
    let store: HomeAssistantStore
    let isExpanded: Bool
    let expand: () -> Void

    @State private var brightnessValue: Double = 0
    @State private var colorTempValue: Double = 0

    private var canExpand: Bool {
        entity.isLight && entity.state == "on" && (entity.supportsBrightness || entity.supportsColorTemperature)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded {
                lightControls
            }
        }
        .onAppear { syncSliderValues() }
        .onChange(of: entity.id) { syncSliderValues() }
        .onChange(of: entity.attributes.brightness) { syncBrightness() }
        .onChange(of: entity.attributes.colorTempKelvin) { syncColorTemperature() }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.systemImage(for: entity.domain))
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.friendlyName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entity.displayState)
                        .font(.caption)
                        .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
                    if let actionError = store.actionErrors[entity.id] {
                        Text(Self.errorLabel(actionError))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            if canExpand {
                disclosureButton
            }
            if store.pendingActions.contains(entity.id) {
                ProgressView().controlSize(.small)
            } else if entity.isAvailable {
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(entity.isAvailable ? 1 : 0.6)
    }

    private var disclosureButton: some View {
        Button(action: expand) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse" : "Expand")
    }

    @ViewBuilder
    private var actionButtons: some View {
        let actions = EntityActionMapping.displayActions(for: entity)
        if actions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(actions) { action in
                    Button(action.title) {
                        Task {
                            await store.callService(
                                domain: action.domain,
                                service: action.service,
                                entityID: entity.id
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var lightControls: some View {
        VStack(spacing: 4) {
            if entity.supportsBrightness {
                brightnessSlider
            }
            if entity.supportsColorTemperature, let range = entity.colorTempRange {
                colorTemperatureSlider(range: range)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var brightnessSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(
                value: $brightnessValue,
                in: 0...100,
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        Task {
                            await store.setBrightness(entityID: entity.id, percent: Int(brightnessValue))
                        }
                    }
                }
            )
            Text("\(Int(brightnessValue))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func colorTemperatureSlider(range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(
                value: $colorTempValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 100,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        Task {
                            await store.setColorTemperature(entityID: entity.id, kelvin: Int(colorTempValue))
                        }
                    }
                }
            )
            Text("\(Int(colorTempValue))K")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func syncSliderValues() {
        syncBrightness()
        syncColorTemperature()
    }

    private func syncBrightness() {
        brightnessValue = Double(entity.brightnessPercent ?? 100)
    }

    private func syncColorTemperature() {
        if let kelvin = entity.attributes.colorTempKelvin {
            colorTempValue = Double(kelvin)
        } else if let range = entity.colorTempRange {
            colorTempValue = Double((range.lowerBound + range.upperBound) / 2)
        } else {
            colorTempValue = 4000
        }
    }

    private static func errorLabel(_ error: HAError) -> String {
        switch error {
        case .missingToken: return "No token"
        case .httpStatus(let code): return "Failed (\(code))"
        case .transport: return "Unreachable"
        case .decoding, .invalidResponse: return "Error"
        default: return "Error"
        }
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