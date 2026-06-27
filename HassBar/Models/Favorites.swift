//
//  Favorites.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

/// Ordered favorite entity configuration.
///
/// Favorites are stored as a stable ordered list of entity ids so the menu
/// can present them in a deterministic order independent of the entity cache.
struct Favorites: Codable, Equatable, Sendable {
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

    /// Move an already-favorited id to `toIndex`, clamped to valid bounds.
    mutating func move(_ id: String, to toIndex: Int) {
        guard let from = entityIDs.firstIndex(of: id) else { return }
        let clamped = min(max(toIndex, 0), entityIDs.count - 1)
        guard from != clamped else { return }
        entityIDs.remove(at: from)
        let insertAt = clamped > from ? clamped - 1 : clamped
        entityIDs.insert(id, at: insertAt)
    }
}