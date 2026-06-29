//
//  HAEntityState.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

/// Attributes payload for a Home Assistant entity state.
/// Only the fields HassBar cares about are modeled; all other keys
/// are ignored by the decoder so unexpected attribute shapes do not fail decoding.
struct HAAttributes: Decodable, Equatable, Sendable {
    var friendlyName: String?
    var unitOfMeasurement: String?
    var brightness: Int?
    var colorTempKelvin: Int?
    var minColorTempKelvin: Int?
    var maxColorTempKelvin: Int?
    var supportedColorModes: [String]?

    enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
        case unitOfMeasurement = "unit_of_measurement"
        case brightness
        case colorTempKelvin = "color_temp_kelvin"
        case minColorTempKelvin = "min_color_temp_kelvin"
        case maxColorTempKelvin = "max_color_temp_kelvin"
        case supportedColorModes = "supported_color_modes"
    }
}

/// A single Home Assistant entity state as returned by `/api/states`
/// or carried by a `state_changed` event.
struct HAEntity: Decodable, Equatable, Identifiable, Sendable {
    let entityID: String
    var state: String
    var attributes: HAAttributes
    var lastChanged: String?
    var lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    var id: String { entityID }

    /// Domain portion of the entity id, e.g. `light` for `light.living_room`.
    var domain: String {
        if let dot = entityID.firstIndex(of: ".") {
            return String(entityID[..<dot])
        }
        return entityID
    }

    /// Entity-local portion after the domain, e.g. `living_room` for `light.living_room`.
    var localID: String {
        if let dot = entityID.firstIndex(of: ".") {
            return String(entityID[entityID.index(after: dot)...])
        }
        return entityID
    }

    /// Friendly name from attributes if present, otherwise the entity id.
    var friendlyName: String { attributes.friendlyName ?? entityID }

    /// State value with unit appended when available, used for compact display.
    var displayState: String {
        if !isAvailable { return state }
        if let unit = attributes.unitOfMeasurement, !unit.isEmpty {
            return "\(state) \(unit)"
        }
        return state
    }

    var isAvailable: Bool {
        state != "unavailable" && state != "unknown"
    }

    // MARK: - Light helpers

    var isLight: Bool { domain == "light" }

    /// Brightness as a percentage (0-100), or `nil` when not reported.
    var brightnessPercent: Int? {
        guard let brightness = attributes.brightness else { return nil }
        return Int((Double(brightness) / 255.0 * 100).rounded())
    }

    /// Whether the light reports brightness support.
    var supportsBrightness: Bool {
        isLight && attributes.brightness != nil
    }

    /// Whether the light reports color temperature support.
    var supportsColorTemperature: Bool {
        guard isLight else { return false }
        if let modes = attributes.supportedColorModes {
            return modes.contains("color_temp")
        }
        return attributes.minColorTempKelvin != nil && attributes.maxColorTempKelvin != nil
    }

    /// Effective color temperature range in Kelvin.
    var colorTempRange: ClosedRange<Int>? {
        guard let min = attributes.minColorTempKelvin, let max = attributes.maxColorTempKelvin else { return nil }
        return min...max
    }
}

/// Home Assistant domains HassBar recognizes for filtering and control.
enum HADomain: String, CaseIterable, Sendable {
    case sensor
    case binarySensor = "binary_sensor"
    case light
    case switchDomain = "switch"
    case cover
    case lock
    case scene
    case script

    /// Whether this domain is part of the first-version controllable set.
    var isControllable: Bool {
        switch self {
        case .light, .switchDomain, .cover, .lock, .scene, .script: return true
        case .sensor, .binarySensor: return false
        }
    }
}