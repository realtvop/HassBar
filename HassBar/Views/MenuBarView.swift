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
                VStack(spacing: 2) {
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
                    }
                }
                .padding(.vertical, 8)
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

// MARK: - Favorite row

private struct FavoriteRow: View {
    let entity: HAEntity
    let store: HomeAssistantStore
    let isExpanded: Bool
    let expand: () -> Void

    @State private var brightnessValue: Double = 0
    @State private var colorTempValue: Double = 0
    @State private var isHovering = false

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
        .onChange(of: entity.attributes.colorTempMireds) { syncColorTemperature() }
        .onChange(of: entity.attributes.minColorTempKelvin) { syncColorTemperature() }
        .onChange(of: entity.attributes.maxColorTempKelvin) { syncColorTemperature() }
        .onChange(of: entity.attributes.minMireds) { syncColorTemperature() }
        .onChange(of: entity.attributes.maxMireds) { syncColorTemperature() }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            leadingControl

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.friendlyName)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(EntityMenuStyle.statusText(for: entity))
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
        .padding(.leading, 46)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }

    private var brightnessSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            GradientSlider(
                value: $brightnessValue,
                range: 0...100,
                step: 1,
                trackStyle: .valueFill(brightnessColor),
                onCommit: {
                    await store.setBrightness(entityID: entity.id, percent: Int(brightnessValue.rounded()))
                }
            )
            Text("\(Int(brightnessValue.rounded()))%")
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
            GradientSlider(
                value: $colorTempValue,
                range: Double(range.lowerBound)...Double(range.upperBound),
                step: 100,
                trackStyle: .fullGradient(colorTemperatureColors(for: range)),
                onCommit: {
                    await store.setColorTemperature(entityID: entity.id, kelvin: Int(colorTempValue))
                }
            )
            Text("\(Int(colorTempValue))K")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var brightnessColor: Color {
        let kelvin = Int(colorTempValue.rounded())
        let components = ColorTemperatureRGB.components(forKelvin: kelvin)
        return Color(red: components.red, green: components.green, blue: components.blue)
            .opacity(brightnessOpacity)
    }

    private var brightnessOpacity: Double {
        min(max(brightnessValue / 100.0, 0), 1)
    }

    private func colorTemperatureColors(for range: ClosedRange<Int>) -> [Color] {
        let samples = 8
        return (0...samples).map { index in
            let progress = Double(index) / Double(samples)
            let kelvin = Double(range.lowerBound) + progress * Double(range.upperBound - range.lowerBound)
            let components = ColorTemperatureRGB.components(forKelvin: Int(kelvin.rounded()))
            return Color(red: components.red, green: components.green, blue: components.blue)
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
        if let kelvin = entity.colorTempKelvin {
            colorTempValue = Double(clampedColorTemperature(kelvin))
        } else if let range = entity.colorTempRange {
            colorTempValue = Double((range.lowerBound + range.upperBound) / 2)
        } else {
            colorTempValue = 4000
        }
    }

    private func clampedColorTemperature(_ kelvin: Int) -> Int {
        guard let range = entity.colorTempRange else { return kelvin }
        return min(max(kelvin, range.lowerBound), range.upperBound)
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

private enum GradientSliderTrackStyle {
    case fullGradient([Color])
    case valueFill(Color)
}

private struct GradientSlider: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double
    let trackStyle: GradientSliderTrackStyle
    let onCommit: () async -> Void

    private let thumbSize: CGFloat = 13
    private let trackHeight: CGFloat = 6
    private let scrollSensitivity = 0.35

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, thumbSize)
            let trackWidth = max(width - thumbSize, 1)
            let progress = normalizedValue

            ZStack(alignment: .leading) {
                track(progress: progress, trackWidth: trackWidth)

                Circle()
                    .fill(.background)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                    .overlay {
                        Circle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .position(x: thumbSize / 2 + trackWidth * progress, y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                SliderEventView { locationX in
                    updateValue(from: locationX, trackWidth: trackWidth)
                } onScroll: { delta in
                    updateValue(byScrollDelta: delta)
                } onCommit: {
                    Task { await onCommit() }
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityValue("\(Int(value))")
    }

    private var normalizedValue: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    @ViewBuilder
    private func track(progress: CGFloat, trackWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            switch trackStyle {
            case .fullGradient(let colors):
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: trackWidth, height: trackHeight)
                    .padding(.leading, thumbSize / 2)
            case .valueFill(let color):
                Capsule()
                    .fill(color)
                    .frame(width: max(trackWidth * progress, 0), height: trackHeight)
                    .padding(.leading, thumbSize / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func updateValue(from locationX: CGFloat, trackWidth: CGFloat) {
        let clampedX = min(max(locationX - thumbSize / 2, 0), trackWidth)
        if clampedX <= 0 {
            value = range.lowerBound
            return
        }
        if clampedX >= trackWidth {
            value = range.upperBound
            return
        }

        let rawValue = range.lowerBound + Double(clampedX / trackWidth) * (range.upperBound - range.lowerBound)
        let steppedValue = range.lowerBound + ((rawValue - range.lowerBound) / step).rounded() * step
        value = min(max(steppedValue, range.lowerBound), range.upperBound)
    }

    private func updateValue(byScrollDelta delta: CGFloat) {
        guard delta != 0, range.upperBound > range.lowerBound else { return }

        let valueRange = range.upperBound - range.lowerBound
        let scrollStep = max(step, valueRange / 100)
        let rawValue = value + Double(delta) * scrollStep * scrollSensitivity
        let steppedValue = range.lowerBound + ((rawValue - range.lowerBound) / step).rounded() * step
        value = min(max(steppedValue, range.lowerBound), range.upperBound)
    }
}

private struct SliderEventView: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void
    let onScroll: (CGFloat) -> Void
    let onCommit: () -> Void

    func makeNSView(context: Context) -> SliderEventCatcherView {
        let view = SliderEventCatcherView()
        view.onDrag = onDrag
        view.onScroll = onScroll
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: SliderEventCatcherView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onScroll = onScroll
        nsView.onCommit = onCommit
    }

    final class SliderEventCatcherView: NSView {
        var onDrag: ((CGFloat) -> Void)?
        var onScroll: ((CGFloat) -> Void)?
        var onCommit: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            handleDrag(event)
        }

        override func mouseDragged(with event: NSEvent) {
            handleDrag(event)
        }

        override func mouseUp(with event: NSEvent) {
            handleDrag(event)
            onCommit?()
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.hasPreciseScrollingDeltas else {
                super.scrollWheel(with: event)
                return
            }
            guard event.momentumPhase == [] else { return }

            let horizontalDelta = event.scrollingDeltaX
            guard abs(horizontalDelta) > abs(event.scrollingDeltaY), horizontalDelta != 0 else {
                super.scrollWheel(with: event)
                return
            }

            let directionMultiplier: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            onScroll?(horizontalDelta * directionMultiplier)

            if event.phase == .ended || event.momentumPhase == .ended {
                onCommit?()
            }
        }

        private func handleDrag(_ event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onDrag?(location.x)
        }
    }
}
