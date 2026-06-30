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
    private let makeClient: (HAConnection) -> any HomeAssistantCalling

    private(set) var status: HAConnectionStatus = .unconfigured
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var isLoading = false
    private(set) var lastError: HAError?

    /// Entity ids with an in-flight service call.
    private(set) var pendingActions: Set<String> = []

    /// Test hook to register a pending action without issuing a service call.
    func registerPendingAction(_ id: String) {
        pendingActions.insert(id)
    }
    /// Removes a pending action; used by tests or WS event application.
    func clearPendingAction(_ id: String) {
        pendingActions.remove(id)
    }
    /// Most recent per-entity service call error.
    private(set) var actionErrors: [String: HAError] = [:]

    private(set) var favorites: Favorites
    private(set) var entityAliases: EntityAliases
    private(set) var entityIcons: EntityIcons
    private(set) var realtimeStatus: HARealtimeStatus = .disconnected

    private var webSocket: HomeAssistantWebSocket?
    let startRealtimeOnRefresh: Bool

    init(
        config: AppConfig,
        startRealtimeOnRefresh: Bool = true,
        makeClient: @escaping (HAConnection) -> any HomeAssistantCalling = { HomeAssistantClient(connection: $0) }
    ) {
        self.config = config
        self.startRealtimeOnRefresh = startRealtimeOnRefresh
        self.makeClient = makeClient
        self.favorites = config.favorites
        self.entityAliases = config.entityAliases
        self.entityIcons = config.entityIcons
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

    func displayName(for entity: HAEntity) -> String {
        entityAliases.name(for: entity.id) ?? entity.friendlyName
    }

    func alias(for entityID: String) -> String {
        entityAliases.name(for: entityID) ?? ""
    }

    func setAlias(_ name: String, for entityID: String) {
        entityAliases.setName(name, for: entityID)
        config.entityAliases = entityAliases
    }

    func customIcon(for entityID: String) -> String {
        entityIcons.icon(for: entityID) ?? ""
    }

    func setCustomIcon(_ iconName: String, for entityID: String) {
        entityIcons.setIcon(iconName, for: entityID)
        config.entityIcons = entityIcons
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
        let client: any HomeAssistantCalling = makeClient(HAConnection(baseURL: url, token: token))

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

    func callService(domain: String, service: String, entityID: String, serviceData: [String: Any]? = nil) async {
        guard config.isConfigured, let url = URL(string: config.haURL), let token = config.token, !token.isEmpty else {
            actionErrors[entityID] = .missingToken
            return
        }
        let client: any HomeAssistantCalling = makeClient(HAConnection(baseURL: url, token: token))

        pendingActions.insert(entityID)
        actionErrors[entityID] = nil
        let previousState = entities[entityID]?.state
        do {
            try await client.callService(domain: domain, service: service, entityID: entityID, serviceData: serviceData)
            // HA may not apply the service call synchronously, so poll the
            // entity state for a short window until it changes (or give up
            // and let WebSocket `state_changed` events handle it). This keeps
            // `pendingActions` set while polling so the spinner stays visible.
            await pollForStateChange(client: client, entityID: entityID, previousState: previousState)
            pendingActions.remove(entityID)
        } catch let error as HAError {
            actionErrors[entityID] = error
            pendingActions.remove(entityID)
        } catch {
            actionErrors[entityID] = .transport(error.localizedDescription)
            pendingActions.remove(entityID)
        }
    }

    // MARK: - Light controls

    /// Sets a light's brightness as a percentage (0-100). A value of 0 turns the light off.
    func setBrightness(entityID: String, percent: Int) async {
        let clamped = max(0, min(100, percent))
        if clamped == 0 {
            await callService(domain: "light", service: "turn_off", entityID: entityID)
        } else {
            let brightness = Int((Double(clamped) / 100.0 * 255).rounded())
            await callService(domain: "light", service: "turn_on", entityID: entityID, serviceData: ["brightness": brightness])
        }
    }

    /// Sets a light's color temperature in Kelvin.
    func setColorTemperature(entityID: String, kelvin: Int) async {
        await callService(domain: "light", service: "turn_on", entityID: entityID, serviceData: ["color_temp_kelvin": kelvin])
    }

    // MARK: - Climate controls

    func setClimateHVACMode(entityID: String, mode: String) async {
        await callService(
            domain: "climate",
            service: "set_hvac_mode",
            entityID: entityID,
            serviceData: ["hvac_mode": mode]
        )
    }

    func setClimateTemperature(entityID: String, temperature: Double) async {
        await callService(
            domain: "climate",
            service: "set_temperature",
            entityID: entityID,
            serviceData: ["temperature": temperature]
        )
    }

    // MARK: - Favorites

    /// Polls the entity state for a short window after a service call,
    /// waiting for HA to apply the change. Updates `entities` and returns
    /// as soon as the state differs from `previousState`. Best-effort:
    /// errors are swallowed and WebSocket events may still apply updates.
    private func pollForStateChange(
        client: any HomeAssistantCalling,
        entityID: String,
        previousState: String?,
        attempts: Int = 6,
        initialDelay: Duration = .milliseconds(300),
        maxDelay: Duration = .milliseconds(1500)
    ) async {
        var delay = initialDelay
        for _ in 0..<attempts {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                let updated = try await client.fetchEntity(entityID: entityID)
                if previousState == nil || updated.state != previousState {
                    entities[entityID] = updated
                    return
                }
                entities[entityID] = updated
            } catch {
                return
            }
            delay = min(delay * 2, maxDelay)
        }
    }

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

    /// Reorder a visible subset of favorites while leaving other favorite groups in place.
    func moveFavoriteSubset(_ entityIDs: [String], from source: IndexSet, to destination: Int) {
        var reorderedIDs = entityIDs
        reorderedIDs.move(fromOffsets: source, toOffset: destination)

        let movedIDSet = Set(entityIDs)
        var reorderedIterator = reorderedIDs.makeIterator()
        favorites.entityIDs = favorites.entityIDs.map { id in
            movedIDSet.contains(id) ? (reorderedIterator.next() ?? id) : id
        }
        config.favorites = favorites
    }

    /// Call when settings (URL/token) have changed outside the store.
    func reloadConfiguration() {
        favorites = config.favorites
        entityAliases = config.entityAliases
        entityIcons = config.entityIcons
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
        guard startRealtimeOnRefresh, config.isConfigured,
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
