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
struct Favorites: Equatable, Sendable {
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

extension Favorites: RawRepresentable {
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