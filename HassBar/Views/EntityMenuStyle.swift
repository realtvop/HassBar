//
//  EntityMenuStyle.swift
//  HassBar
//
//  Created by Codex on 2026/6/29.
//

import SwiftUI

enum EntityMenuStyle {
    static let hoverBackground = Color(nsColor: .separatorColor).opacity(0.22)

    static func systemImage(for domain: String) -> String {
        switch HADomain(rawValue: domain) {
        case .sensor: return "gauge.with.dots.needle.bottom.50percent"
        case .binarySensor: return "sensor.tag.radiowaves.forward"
        case .light: return "lightbulb.fill"
        case .switchDomain: return "switch.2"
        case .cover: return "blinds.horizontal.closed"
        case .lock: return "lock.fill"
        case .scene: return "sparkles"
        case .script: return "applescript.fill"
        default: return "circle.grid.2x2.fill"
        }
    }

    static func iconTint(for entity: HAEntity) -> Color {
        if !entity.isAvailable { return .secondary }
        switch HADomain(rawValue: entity.domain) {
        case .light where entity.state == "on": return .yellow
        case .switchDomain where entity.state == "on": return .blue
        case .lock where entity.state == "locked": return .green
        case .cover where entity.state == "open": return .blue
        case .scene, .script: return .purple
        case .sensor, .binarySensor: return .secondary
        default: return .secondary
        }
    }

    static func statusText(for entity: HAEntity) -> String {
        if entity.displayState.isEmpty { return entity.entityID }
        return entity.displayState
    }

    static func isActive(_ entity: HAEntity) -> Bool {
        switch HADomain(rawValue: entity.domain) {
        case .light, .switchDomain:
            return entity.state == "on"
        case .lock:
            return entity.state == "locked"
        case .cover:
            return entity.state == "open"
        default:
            return false
        }
    }
}

struct EntityIconBadge: View {
    let entity: HAEntity
    var customIconName: String? = nil
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(iconBackground)
            resolvedIcon
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(EntityMenuStyle.iconTint(for: entity))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var resolvedIcon: some View {
        if let customIconName, !customIconName.isEmpty, NSImage(systemSymbolName: customIconName, accessibilityDescription: nil) != nil {
            Image(systemName: customIconName)
        } else {
            Image(systemName: EntityMenuStyle.systemImage(for: entity.domain))
        }
    }

    private var iconBackground: Color {
        if EntityMenuStyle.isActive(entity) {
            return EntityMenuStyle.iconTint(for: entity).opacity(0.18)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }
}
