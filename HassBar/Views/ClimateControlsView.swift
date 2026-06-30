//
//  ClimateControlsView.swift
//  HassBar
//
//  Created by Codex on 2026/7/1.
//

import SwiftUI

struct ClimateControlsView: View {
    let entity: HAEntity
    let store: HomeAssistantStore

    @State private var targetTemperature: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            if !hvacModes.isEmpty {
                hvacModePicker
            }
            if let range = entity.climateTemperatureRange {
                temperatureSlider(range: range)
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onAppear { syncTargetTemperature() }
        .onChange(of: entity.id) { syncTargetTemperature() }
        .onChange(of: entity.attributes.targetTemperature) { syncTargetTemperature() }
        .onChange(of: entity.attributes.minTemperature) { syncTargetTemperature() }
        .onChange(of: entity.attributes.maxTemperature) { syncTargetTemperature() }
    }

    private var hvacModePicker: some View {
        HStack(spacing: 6) {
            ForEach(hvacModes, id: \.self) { mode in
                Button {
                    Task {
                        await store.setClimateHVACMode(entityID: entity.id, mode: mode)
                    }
                } label: {
                    Image(systemName: iconName(for: mode))
                        .font(.caption)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .background {
                    if entity.state == mode {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
                .foregroundStyle(entity.state == mode ? Color.accentColor : Color.secondary)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .help(label(for: mode))
            }
            Spacer(minLength: 0)
        }
    }

    private func temperatureSlider(range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.medium")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            GradientSlider(
                value: $targetTemperature,
                range: range,
                step: entity.climateTemperatureStep,
                trackStyle: .fullGradient([.blue.opacity(0.8), .cyan.opacity(0.75), .orange.opacity(0.9)]),
                onCommit: { value in
                    await store.setClimateTemperature(entityID: entity.id, temperature: roundedTemperature(value))
                }
            )
            Text(temperatureText(targetTemperature))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var hvacModes: [String] {
        entity.climateHVACModes
    }

    private func syncTargetTemperature() {
        if let temperature = entity.climateTargetTemperature {
            targetTemperature = clampedTemperature(temperature)
        } else if let range = entity.climateTemperatureRange {
            targetTemperature = roundedTemperature((range.lowerBound + range.upperBound) / 2)
        }
    }

    private func clampedTemperature(_ temperature: Double) -> Double {
        guard let range = entity.climateTemperatureRange else { return roundedTemperature(temperature) }
        return roundedTemperature(min(max(temperature, range.lowerBound), range.upperBound))
    }

    private func roundedTemperature(_ temperature: Double) -> Double {
        let step = entity.climateTemperatureStep
        guard step > 0 else { return temperature }
        return (temperature / step).rounded() * step
    }

    private func temperatureText(_ temperature: Double) -> String {
        let rounded = roundedTemperature(temperature)
        let hasFraction = rounded.truncatingRemainder(dividingBy: 1) != 0
        let number = hasFraction ? String(format: "%.1f", rounded) : String(format: "%.0f", rounded)
        return "\(number)\(entity.climateTemperatureUnit)"
    }

    private func iconName(for mode: String) -> String {
        switch mode {
        case "off": return "power"
        case "cool": return "snowflake"
        case "heat": return "flame.fill"
        case "heat_cool": return "arrow.triangle.2.circlepath"
        case "auto": return "a.circle"
        case "dry": return "drop.degreesign.slash"
        case "fan_only": return "fan.fill"
        default: return "circle"
        }
    }

    private func label(for mode: String) -> String {
        switch mode {
        case "off": return "Off"
        case "cool": return "Cool"
        case "heat": return "Heat"
        case "heat_cool": return "Heat/Cool"
        case "auto": return "Auto"
        case "dry": return "Dry"
        case "fan_only": return "Fan Only"
        default:
            return mode
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
