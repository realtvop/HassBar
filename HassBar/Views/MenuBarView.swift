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

    private var sensorRows: [HAEntity] {
        store.favoriteRows.filter { Self.isSensor($0) }
    }

    private var controlRows: [HAEntity] {
        store.favoriteRows.filter { !Self.isSensor($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 340)
        .background(.regularMaterial)
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
        .overlay(alignment: .bottom) {
            Divider()
        }
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
        case .error(let error): return Text(Self.errorLabel(error))
        }
    }

    private static func isSensor(_ entity: HAEntity) -> Bool {
        entity.domain == HADomain.sensor.rawValue || entity.domain == HADomain.binarySensor.rawValue
    }

    private static func errorLabel(_ error: HAError) -> String {
        switch error {
        case .missingToken: return "Missing token"
        case .invalidResponse: return "Invalid response"
        case .httpStatus(let code): return "HTTP \(code)"
        case .transport: return "Could not reach server"
        case .decoding: return "Decode error"
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
                VStack(spacing: 8) {
                    if !sensorRows.isEmpty {
                        SensorStatusSection(entities: sensorRows, store: store)
                    }

                    if !controlRows.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(controlRows) { entity in
                                FavoriteRow(
                                    entity: entity,
                                    store: store,
                                    isExpanded: expandedEntityID == entity.id,
                                    expand: {
                                        withAnimation(.hassBarDisclosure) {
                                            expandedEntityID = (expandedEntityID == entity.id ? nil : entity.id)
                                        }
                                    },
                                    collapse: {
                                        withAnimation(.hassBarDisclosure) {
                                            if expandedEntityID == entity.id {
                                                expandedEntityID = nil
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .onChange(of: controlRows.map(\.id)) { _, ids in
                    if let expandedEntityID, !ids.contains(expandedEntityID) {
                        withAnimation(.hassBarDisclosure) {
                            self.expandedEntityID = nil
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
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Sensor status section

private struct SensorStatusSection: View {
    let entities: [HAEntity]
    let store: HomeAssistantStore

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entities) { entity in
                SensorStatusTile(entity: entity, displayName: store.displayName(for: entity))
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct SensorStatusTile: View {
    let entity: HAEntity
    let displayName: String

    var body: some View {
        HStack(spacing: 8) {
            EntityIconBadge(entity: entity, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
                Text(EntityMenuStyle.statusText(for: entity))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entity.isAvailable ? Color.primary : Color.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(entity.isAvailable ? 1 : 0.6)
    }
}

// MARK: - Favorite row

private struct FavoriteRow: View {
    let entity: HAEntity
    let store: HomeAssistantStore
    let isExpanded: Bool
    let expand: () -> Void
    let collapse: () -> Void

    @State private var isHovering = false

    private var canExpand: Bool {
        entity.isLight && entity.state == "on" && (entity.supportsBrightness || entity.supportsColorTemperature)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if showsLightControls {
                LightControlsView(entity: entity, store: store)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
            }
        }
        .animation(.hassBarDisclosure, value: showsLightControls)
        .onChange(of: canExpand) { _, canExpand in
            if !canExpand, isExpanded {
                collapse()
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            leadingControl

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName(for: entity))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(EntityMenuStyle.statusText(for: entity))
                            .font(.caption)
                            .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
                        ForEach(compactLightDetails, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let actionError = store.actionErrors[entity.id] {
                            Text(Self.errorLabel(actionError))
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer()

                if canExpand {
                    disclosureIndicator
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if canExpand {
                    expand()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 6)
                    .fill(EntityMenuStyle.hoverBackground)
            }
        }
        .onHover { isHovering = $0 }
        .opacity(entity.isAvailable ? 1 : 0.6)
    }

    @ViewBuilder
    private var leadingControl: some View {
        if store.pendingActions.contains(entity.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else if let action = primaryAction, entity.isAvailable {
            Button {
                Task {
                    await store.callService(
                        domain: action.domain,
                        service: action.service,
                        entityID: entity.id
                    )
                }
            } label: {
                EntityIconBadge(entity: entity, size: 28)
            }
            .buttonStyle(.plain)
            .help(action.title)
        } else {
            EntityIconBadge(entity: entity, size: 28)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }

    private var primaryAction: EntityAction? {
        EntityActionMapping.displayActions(for: entity).first
    }

    private var showsLightControls: Bool {
        isExpanded && canExpand
    }

    private var compactLightDetails: [String] {
        guard entity.isLight, entity.isAvailable, entity.state == "on" else { return [] }

        var details: [String] = []
        if let brightness = entity.brightnessPercent {
            details.append("\(brightness)%")
        }
        if let colorTempKelvin = entity.colorTempKelvin {
            details.append("\(colorTempKelvin)K")
        }
        return details
    }

    private static func errorLabel(_ error: HAError) -> String {
        switch error {
        case .missingToken: return "No token"
        case .httpStatus(let code): return "Failed (\(code))"
        case .transport: return "Unreachable"
        case .decoding, .invalidResponse: return "Error"
        }
    }

}

private extension Animation {
    static var hassBarDisclosure: Animation {
        .interpolatingSpring(mass: 0.7, stiffness: 280, damping: 28, initialVelocity: 0)
    }
}
