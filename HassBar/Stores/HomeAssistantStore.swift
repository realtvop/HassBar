//
//  HomeAssistantStore.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation
import Observation
import SwiftUI

/// High-level connection state surfaced to the UI.
enum HAConnectionStatus: Equatable, Sendable {
    case unconfigured
    case disconnected
    case connecting
    case connected
    case error(HAError)
}

/// Observable application state bridging `HomeAssistantClient` and SwiftUI views.
@MainActor
@Observable
final class HomeAssistantStore: HAWebsocketDelegate {
    let config: AppConfig
    private let makeClient: (HAConnection) -> HomeAssistantClient

    private(set) var status: HAConnectionStatus = .unconfigured
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var isLoading = false
    private(set) var lastError: HAError?

    /// Entity ids with an in-flight service call.
    private(set) var pendingActions: Set<String> = []
    /// Most recent per-entity service call error.
    private(set) var actionErrors: [String: HAError] = [:]

    private(set) var favorites: Favorites
    private(set) var realtimeStatus: HARealtimeStatus = .disconnected

    private var webSocket: HomeAssistantWebSocket?

    init(
        config: AppConfig,
        makeClient: @escaping (HAConnection) -> HomeAssistantClient = { HomeAssistantClient(connection: $0) }
    ) {
        self.config = config
        self.makeClient = makeClient
        self.favorites = config.favorites
        refreshStatus()
    }

    // MARK: - Derived views

    var favoriteRows: [HAEntity] {
        favorites.entityIDs.compactMap { entities[$0] }
    }

    /// Entities sorted by entity_id for the selection window.
    var allEntitiesSorted: [HAEntity] {
        entities.values.sorted { $0.entityID < $1.entityID }
    }

    func entity(for id: String) -> HAEntity? {
        entities[id]
    }

    // MARK: - Loading

    /// Re-fetch `/api/states`. Keeps last known entities on failure.
    func refresh() async {
        guard config.isConfigured else {
            status = .unconfigured
            return
        }
        guard let url = URL(string: config.haURL), let token = config.token, !token.isEmpty else {
            status = .unconfigured
            return
        }
        let client = makeClient(HAConnection(baseURL: url, token: token))

        isLoading = true
        status = .connecting
        do {
            let states = try await client.fetchStates()
            var cache: [String: HAEntity] = [:]
            cache.reserveCapacity(states.count)
            for entity in states {
                cache[entity.entityID] = entity
            }
            entities = cache
            lastError = nil
            status = .connected
            startRealtimeIfNeeded()
        } catch let error as HAError {
            lastError = error
            status = .error(error)
        } catch {
            lastError = .transport(error.localizedDescription)
            status = .error(.transport(error.localizedDescription))
        }
        isLoading = false
    }

    /// Convenience for view appearance: refresh once if configured.
    func refreshIfConfigured() async {
        guard config.isConfigured else { return }
        await refresh()
    }

    // MARK: - Service calls

    func callService(domain: String, service: String, entityID: String) async {
        guard config.isConfigured, let url = URL(string: config.haURL), let token = config.token, !token.isEmpty else {
            actionErrors[entityID] = .missingToken
            return
        }
        let client = makeClient(HAConnection(baseURL: url, token: token))

        pendingActions.insert(entityID)
        actionErrors[entityID] = nil
        do {
            try await client.callService(domain: domain, service: service, entityID: entityID)
            // State is expected to update via WebSocket `state_changed` events,
            // which clear `pendingActions` when the new state arrives. We also
            // clear pending as a fallback here.
            pendingActions.remove(entityID)
        } catch let error as HAError {
            actionErrors[entityID] = error
            pendingActions.remove(entityID)
        } catch {
            actionErrors[entityID] = .transport(error.localizedDescription)
            pendingActions.remove(entityID)
        }
    }

    // MARK: - Favorites

    func toggleFavorite(_ id: String) {
        favorites.toggle(id)
        config.favorites = favorites
    }

    func moveFavorite(_ id: String, to index: Int) {
        favorites.move(id, to: index)
        config.favorites = favorites
    }

    /// Reorder favorites from a SwiftUI `onMove` operation.
    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.entityIDs.move(fromOffsets: source, toOffset: destination)
        config.favorites = favorites
    }

    /// Call when settings (URL/token) have changed outside the store.
    func reloadConfiguration() {
        favorites = config.favorites
        refreshStatus()
    }

    // MARK: - Internal

    private func refreshStatus() {
        if config.isConfigured {
            if case .unconfigured = status { status = .disconnected }
        } else {
            status = .unconfigured
        }
    }

    // MARK: - WebSocket

    private func startRealtimeIfNeeded() {
        guard config.isConfigured,
              let url = URL(string: config.haURL),
              let token = config.token, !token.isEmpty else { return }
        if let webSocket {
            Task { await webSocket.stop() }
        }
        let ws = HomeAssistantWebSocket(baseURL: url, token: token, delegate: self)
        webSocket = ws
        Task { await ws.start() }
    }

    func stopRealtime() {
        if let ws = webSocket {
            Task { await ws.stop() }
        }
        webSocket = nil
        realtimeStatus = .disconnected
    }

    nonisolated func realtime(didChange status: HARealtimeStatus) {
        Task { @MainActor in
            self.realtimeStatus = status
        }
    }

    nonisolated func realtime(didReceive event: HAWebsocketEvent) {
        Task { @MainActor in
            self.applyRealtimeEvent(event)
        }
    }

    @MainActor
    private func applyRealtimeEvent(_ event: HAWebsocketEvent) {
        switch event {
        case .stateChanged(_, let entity):
            entities[entity.entityID] = entity
            // Clear any pending action once the new state arrives.
            pendingActions.remove(entity.entityID)
        case .unknown:
            break
        }
    }
}