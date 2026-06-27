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

    enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
        case unitOfMeasurement = "unit_of_measurement"
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