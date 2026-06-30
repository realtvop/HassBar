//
//  LightControlsView.swift
//  HassBar
//
//  Created by Codex on 2026/6/30.
//

import SwiftUI

struct LightControlsView: View {
    let entity: HAEntity
    let store: HomeAssistantStore

    @State private var brightnessValue: Double = 0
    @State private var colorTempValue: Double = 0

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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
                onCommit: { value in
                    await store.setBrightness(entityID: entity.id, percent: Int(value.rounded()))
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
                onCommit: { value in
                    await store.setColorTemperature(entityID: entity.id, kelvin: Int(value.rounded()))
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
}
