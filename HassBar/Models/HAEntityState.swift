//
//  HAEntityState.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

struct RGBColorComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

enum ColorTemperatureRGB {
    static func components(forKelvin kelvin: Int) -> RGBColorComponents {
        let temperature = Double(min(max(kelvin, 1_000), 40_000)) / 100.0
        let red: Double
        let green: Double
        let blue: Double

        if temperature <= 66 {
            red = 255
            green = 99.4708025861 * log(temperature) - 161.1195681661
        } else {
            red = 329.698727446 * pow(temperature - 60, -0.1332047592)
            green = 288.1221695283 * pow(temperature - 60, -0.0755148492)
        }

        if temperature >= 66 {
            blue = 255
        } else if temperature <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(temperature - 10) - 305.0447927307
        }

        return RGBColorComponents(
            red: clampedChannel(red) / 255.0,
            green: clampedChannel(green) / 255.0,
            blue: clampedChannel(blue) / 255.0
        )
    }

    private static func clampedChannel(_ value: Double) -> Double {
        min(max(value, 0), 255)
    }
}

/// Attributes payload for a Home Assistant entity state.
/// Only the fields HassBar cares about are modeled; all other keys
/// are ignored by the decoder so unexpected attribute shapes do not fail decoding.
struct HAAttributes: Decodable, Equatable, Sendable {
    var friendlyName: String?
    var unitOfMeasurement: String?
    var brightness: Int?
    var colorTempKelvin: Int?
    var colorTempMireds: Int?
    var minColorTempKelvin: Int?
    var maxColorTempKelvin: Int?
    var minMireds: Int?
    var maxMireds: Int?
    var supportedColorModes: [String]?
    var currentTemperature: Double?
    var targetTemperature: Double?
    var minTemperature: Double?
    var maxTemperature: Double?
    var targetTemperatureStep: Double?
    var temperatureUnit: String?
    var hvacModes: [String]?

    enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
        case unitOfMeasurement = "unit_of_measurement"
        case brightness
        case colorTempKelvin = "color_temp_kelvin"
        case colorTempMireds = "color_temp"
        case minColorTempKelvin = "min_color_temp_kelvin"
        case maxColorTempKelvin = "max_color_temp_kelvin"
        case minMireds = "min_mireds"
        case maxMireds = "max_mireds"
        case supportedColorModes = "supported_color_modes"
        case currentTemperature = "current_temperature"
        case targetTemperature = "temperature"
        case minTemperature = "min_temp"
        case maxTemperature = "max_temp"
        case targetTemperatureStep = "target_temp_step"
        case temperatureUnit = "temperature_unit"
        case hvacModes = "hvac_modes"
    }

    init(
        friendlyName: String?,
        unitOfMeasurement: String?,
        brightness: Int? = nil,
        colorTempKelvin: Int? = nil,
        colorTempMireds: Int? = nil,
        minColorTempKelvin: Int? = nil,
        maxColorTempKelvin: Int? = nil,
        minMireds: Int? = nil,
        maxMireds: Int? = nil,
        supportedColorModes: [String]? = nil,
        currentTemperature: Double? = nil,
        targetTemperature: Double? = nil,
        minTemperature: Double? = nil,
        maxTemperature: Double? = nil,
        targetTemperatureStep: Double? = nil,
        temperatureUnit: String? = nil,
        hvacModes: [String]? = nil
    ) {
        self.friendlyName = friendlyName
        self.unitOfMeasurement = unitOfMeasurement
        self.brightness = brightness
        self.colorTempKelvin = colorTempKelvin
        self.colorTempMireds = colorTempMireds
        self.minColorTempKelvin = minColorTempKelvin
        self.maxColorTempKelvin = maxColorTempKelvin
        self.minMireds = minMireds
        self.maxMireds = maxMireds
        self.supportedColorModes = supportedColorModes
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
        self.targetTemperatureStep = targetTemperatureStep
        self.temperatureUnit = temperatureUnit
        self.hvacModes = hvacModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendlyName = try container.decodeIfPresent(String.self, forKey: .friendlyName)
        unitOfMeasurement = try container.decodeIfPresent(String.self, forKey: .unitOfMeasurement)
        brightness = container.decodeLossyIntIfPresent(forKey: .brightness)
        colorTempKelvin = container.decodeLossyIntIfPresent(forKey: .colorTempKelvin)
        colorTempMireds = container.decodeLossyIntIfPresent(forKey: .colorTempMireds)
        minColorTempKelvin = container.decodeLossyIntIfPresent(forKey: .minColorTempKelvin)
        maxColorTempKelvin = container.decodeLossyIntIfPresent(forKey: .maxColorTempKelvin)
        minMireds = container.decodeLossyIntIfPresent(forKey: .minMireds)
        maxMireds = container.decodeLossyIntIfPresent(forKey: .maxMireds)
        supportedColorModes = try? container.decodeIfPresent([String].self, forKey: .supportedColorModes)
        currentTemperature = container.decodeLossyDoubleIfPresent(forKey: .currentTemperature)
        targetTemperature = container.decodeLossyDoubleIfPresent(forKey: .targetTemperature)
        minTemperature = container.decodeLossyDoubleIfPresent(forKey: .minTemperature)
        maxTemperature = container.decodeLossyDoubleIfPresent(forKey: .maxTemperature)
        targetTemperatureStep = container.decodeLossyDoubleIfPresent(forKey: .targetTemperatureStep)
        temperatureUnit = try? container.decodeIfPresent(String.self, forKey: .temperatureUnit)
        hvacModes = try? container.decodeIfPresent([String].self, forKey: .hvacModes)
    }
}

private extension KeyedDecodingContainer where K == HAAttributes.CodingKeys {
    func decodeLossyIntIfPresent(forKey key: K) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let number = Double(value) {
            return Int(number.rounded())
        }
        return nil
    }

    func decodeLossyDoubleIfPresent(forKey key: K) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
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
        return colorTempRange != nil
    }

    /// Effective color temperature range in Kelvin.
    var colorTempRange: ClosedRange<Int>? {
        if let min = attributes.minColorTempKelvin, let max = attributes.maxColorTempKelvin {
            return min...max
        }
        guard
            let minMireds = attributes.minMireds,
            let maxMireds = attributes.maxMireds,
            let warmKelvin = Self.kelvin(fromMireds: maxMireds),
            let coolKelvin = Self.kelvin(fromMireds: minMireds)
        else {
            return nil
        }
        return min(warmKelvin, coolKelvin)...max(warmKelvin, coolKelvin)
    }

    var colorTempKelvin: Int? {
        if let kelvin = attributes.colorTempKelvin {
            return kelvin
        }
        guard let mireds = attributes.colorTempMireds else { return nil }
        return Self.kelvin(fromMireds: mireds)
    }

    private static func kelvin(fromMireds mireds: Int) -> Int? {
        guard mireds > 0 else { return nil }
        return Int((1_000_000.0 / Double(mireds)).rounded())
    }

    // MARK: - Climate helpers

    var isClimate: Bool { domain == "climate" }

    var isClimateActive: Bool {
        isClimate && isAvailable && state != "off"
    }

    var climateTemperatureUnit: String {
        attributes.temperatureUnit ?? attributes.unitOfMeasurement ?? "°"
    }

    var climateTemperatureStep: Double {
        if let step = attributes.targetTemperatureStep, step > 0 {
            return step
        }
        return climateTemperatureUnit == "°F" ? 1 : 0.5
    }

    var climateTemperatureRange: ClosedRange<Double>? {
        guard let min = attributes.minTemperature, let max = attributes.maxTemperature, min < max else {
            return nil
        }
        return min...max
    }

    var climateTargetTemperature: Double? {
        attributes.targetTemperature
    }

    var climateCurrentTemperature: Double? {
        attributes.currentTemperature
    }

    var climateHVACModes: [String] {
        attributes.hvacModes ?? []
    }
}

/// Home Assistant domains HassBar recognizes for filtering and control.
enum HADomain: String, CaseIterable, Sendable {
    case sensor
    case binarySensor = "binary_sensor"
    case light
    case climate
    case switchDomain = "switch"
    case cover
    case lock
    case scene
    case script

    /// Whether this domain is part of the first-version controllable set.
    var isControllable: Bool {
        switch self {
        case .light, .climate, .switchDomain, .cover, .lock, .scene, .script: return true
        case .sensor, .binarySensor: return false
        }
    }
}
