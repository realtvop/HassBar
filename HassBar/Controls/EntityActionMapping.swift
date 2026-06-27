//
//  EntityActionMapping.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

/// A user-invokable action on a Home Assistant entity, mapped to a service call.
struct EntityAction: Identifiable, Hashable, Sendable {
    let id: String          // e.g. "turn_on"
    let title: String       // e.g. "Turn On"
    let domain: String
    let service: String
}

/// Converts a Home Assistant entity domain into one or more UI actions
/// backed by service calls. Domains without a mapping are read-only.
enum EntityActionMapping {
    static func actions(for entity: HAEntity) -> [EntityAction] {
        guard let domain = HADomain(rawValue: entity.domain) else { return [] }
        switch domain {
        case .switchDomain, .light:
            return [
                .init(id: "turn_on", title: "Turn On", domain: entity.domain, service: "turn_on"),
                .init(id: "turn_off", title: "Turn Off", domain: entity.domain, service: "turn_off"),
                .init(id: "toggle", title: "Toggle", domain: entity.domain, service: "toggle"),
            ]
        case .cover:
            return [
                .init(id: "open_cover", title: "Open", domain: entity.domain, service: "open_cover"),
                .init(id: "close_cover", title: "Close", domain: entity.domain, service: "close_cover"),
                .init(id: "stop_cover", title: "Stop", domain: entity.domain, service: "stop_cover"),
            ]
        case .lock:
            return [
                .init(id: "lock", title: "Lock", domain: entity.domain, service: "lock"),
                .init(id: "unlock", title: "Unlock", domain: entity.domain, service: "unlock"),
            ]
        case .scene, .script:
            return [
                .init(id: "turn_on", title: "Run", domain: entity.domain, service: "turn_on"),
            ]
        case .sensor, .binarySensor:
            return []
        }
    }

    /// State-aware subset of `actions(for:)` suitable for compact display.
    /// For binary-action domains this returns a single contextual button
    /// (e.g. Turn Off when the entity is on); for `cover` it also keeps Stop.
    static func displayActions(for entity: HAEntity) -> [EntityAction] {
        guard let domain = HADomain(rawValue: entity.domain) else { return [] }
        switch domain {
        case .switchDomain, .light:
            let on = entity.state == "on"
            let service = on ? "turn_off" : "turn_on"
            let title = on ? "Turn Off" : "Turn On"
            return [.init(id: service, title: title, domain: entity.domain, service: service)]
        case .cover:
            let primary: EntityAction
            if entity.state == "open" {
                primary = .init(id: "close_cover", title: "Close", domain: entity.domain, service: "close_cover")
            } else {
                primary = .init(id: "open_cover", title: "Open", domain: entity.domain, service: "open_cover")
            }
            let stop = EntityAction(id: "stop_cover", title: "Stop", domain: entity.domain, service: "stop_cover")
            return [primary, stop]
        case .lock:
            if entity.state == "locked" {
                return [.init(id: "unlock", title: "Unlock", domain: entity.domain, service: "unlock")]
            } else {
                return [.init(id: "lock", title: "Lock", domain: entity.domain, service: "lock")]
            }
        case .scene, .script:
            return actions(for: entity)
        case .sensor, .binarySensor:
            return []
        }
    }
}