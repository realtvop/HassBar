//
//  Favorites.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation
import SwiftUI

/// Ordered favorite entity configuration.
///
/// Favorites are stored as a stable ordered list of entity ids so the menu
/// can present them in a deterministic order independent of the entity cache.
nonisolated struct Favorites: Equatable, Sendable {
    var entityIDs: [String]

    init(entityIDs: [String] = []) {
        self.entityIDs = entityIDs
    }

    func contains(_ id: String) -> Bool {
        entityIDs.contains(id)
    }

    func orderedIndex(of id: String) -> Int? {
        entityIDs.firstIndex(of: id)
    }

    /// Add the id at the end if not already favorited.
    mutating func add(_ id: String) {
        guard !contains(id) else { return }
        entityIDs.append(id)
    }

    /// Remove the id if present.
    mutating func remove(_ id: String) {
        entityIDs.removeAll { $0 == id }
    }

    /// Toggle membership and return the new membership state.
    @discardableResult
    mutating func toggle(_ id: String) -> Bool {
        if contains(id) {
            remove(id)
            return false
        } else {
            add(id)
            return true
        }
    }

    /// Reorders favorites using the same semantics as `Array.move(fromOffsets:toOffset:)`
    /// and SwiftUI `List.onMove`, so callers can pass through `onMove` offsets.
    mutating func move(_ id: String, to destination: Int) {
        guard let from = entityIDs.firstIndex(of: id) else { return }
        let source = IndexSet(integer: from)
        entityIDs.move(fromOffsets: source, toOffset: destination)
    }
}

nonisolated extension Favorites: RawRepresentable {
    /// JSON-encoded `entityIDs` array, used for `UserDefaults` persistence.
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        self.entityIDs = ids
    }

    public var rawValue: String {
        (try? String(data: JSONEncoder().encode(entityIDs), encoding: .utf8)) ?? "[]"
    }
}

/// User-defined display aliases keyed by Home Assistant entity id.
nonisolated struct EntityAliases: Equatable, Sendable {
    private(set) var namesByEntityID: [String: String]

    init(namesByEntityID: [String: String] = [:]) {
        self.namesByEntityID = namesByEntityID.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func name(for id: String) -> String? {
        namesByEntityID[id]
    }

    mutating func setName(_ name: String, for id: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            namesByEntityID[id] = nil
        } else {
            namesByEntityID[id] = trimmed
        }
    }
}

nonisolated extension EntityAliases: RawRepresentable {
    /// JSON-encoded alias dictionary, used for `UserDefaults` persistence.
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        self.init(namesByEntityID: names)
    }

    public var rawValue: String {
        (try? String(data: JSONEncoder().encode(namesByEntityID), encoding: .utf8)) ?? "{}"
    }
}

/// User-defined display icons keyed by Home Assistant entity id.
nonisolated struct EntityIcons: Equatable, Sendable {
    private(set) var iconsByEntityID: [String: String]

    init(iconsByEntityID: [String: String] = [:]) {
        self.iconsByEntityID = iconsByEntityID.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func icon(for id: String) -> String? {
        iconsByEntityID[id]
    }

    mutating func setIcon(_ icon: String, for id: String) {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            iconsByEntityID[id] = nil
        } else {
            iconsByEntityID[id] = trimmed
        }
    }
}

/// Ordered sensors to show directly in the macOS menu bar status item.
nonisolated struct MenuBarSensorItem: Codable, Equatable, Identifiable, Sendable {
    var entityID: String
    var iconName: String
    var showsIcon: Bool

    var id: String { entityID }

    init(entityID: String, iconName: String = "", showsIcon: Bool = true) {
        self.entityID = entityID
        self.iconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.showsIcon = showsIcon
    }
}

nonisolated struct MenuBarSensors: Equatable, Sendable {
    private(set) var items: [MenuBarSensorItem]

    init(items: [MenuBarSensorItem] = []) {
        var seen: Set<String> = []
        self.items = items.compactMap { item in
            guard !item.entityID.isEmpty, !seen.contains(item.entityID) else { return nil }
            seen.insert(item.entityID)
            return MenuBarSensorItem(
                entityID: item.entityID,
                iconName: item.iconName,
                showsIcon: item.showsIcon
            )
        }
    }

    func contains(_ id: String) -> Bool {
        items.contains { $0.entityID == id }
    }

    func item(for id: String) -> MenuBarSensorItem? {
        items.first { $0.entityID == id }
    }

    mutating func add(_ id: String) {
        guard !contains(id) else { return }
        items.append(MenuBarSensorItem(entityID: id))
    }

    mutating func remove(_ id: String) {
        items.removeAll { $0.entityID == id }
    }

    mutating func setIconName(_ iconName: String, for id: String) {
        guard let index = items.firstIndex(where: { $0.entityID == id }) else { return }
        items[index].iconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setShowsIcon(_ showsIcon: Bool, for id: String) {
        guard let index = items.firstIndex(where: { $0.entityID == id }) else { return }
        items[index].showsIcon = showsIcon
    }

    mutating func move(_ id: String, to destination: Int) {
        guard let from = items.firstIndex(where: { $0.entityID == id }) else { return }
        items.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
    }

    mutating func moveSubset(_ entityIDs: [String], from source: IndexSet, to destination: Int) {
        var reorderedIDs = entityIDs
        reorderedIDs.move(fromOffsets: source, toOffset: destination)

        let movedIDSet = Set(entityIDs)
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.entityID, $0) })
        var reorderedIterator = reorderedIDs.makeIterator()
        items = items.map { item in
            guard movedIDSet.contains(item.entityID), let nextID = reorderedIterator.next(),
                  let replacement = itemsByID[nextID] else {
                return item
            }
            return replacement
        }
    }
}

nonisolated extension MenuBarSensors: RawRepresentable {
    /// JSON-encoded ordered sensor item array, used for `UserDefaults` persistence.
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let items = try? JSONDecoder().decode([MenuBarSensorItem].self, from: data) else {
            return nil
        }
        self.init(items: items)
    }

    public var rawValue: String {
        (try? String(data: JSONEncoder().encode(items), encoding: .utf8)) ?? "[]"
    }
}

nonisolated extension EntityIcons: RawRepresentable {
    /// JSON-encoded icon dictionary, used for `UserDefaults` persistence.
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let icons = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        self.init(iconsByEntityID: icons)
    }

    public var rawValue: String {
        (try? String(data: JSONEncoder().encode(iconsByEntityID), encoding: .utf8)) ?? "{}"
    }
}
