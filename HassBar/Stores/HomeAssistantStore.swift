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

struct MenuBarSensorRow: Identifiable, Equatable {
    let item: MenuBarSensorItem
    let entity: HAEntity

    var id: String { item.entityID }
}

/// Observable application state bridging `HomeAssistantClient` and SwiftUI views.
@MainActor
@Observable
final class HomeAssistantStore: HAWebsocketDelegate {
    let config: AppConfig
    private let makeClient: @MainActor (HAConnection) -> any HomeAssistantCalling

    private(set) var status: HAConnectionStatus = .unconfigured
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var isLoading = false
    private(set) var lastError: HAError?

    /// Entity ids with an in-flight service call.
    private(set) var pendingActions: Set<String> = []
    private var actionIDs: [String: UUID] = [:]
    private var actionServices: [String: String] = [:]

    /// Most recent per-entity service call error.
    private(set) var actionErrors: [String: HAError] = [:]

    private(set) var favorites: Favorites
    private(set) var entityAliases: EntityAliases
    private(set) var entityIcons: EntityIcons
    private(set) var menuBarSensors: MenuBarSensors
    private(set) var showsAppIconInMenuBar: Bool
    private(set) var realtimeStatus: HARealtimeStatus = .disconnected

    private var webSocket: (any HARealtimeConnecting)?
    private var realtimeSink: HARealtimeSink?
    private var realtimeGeneration = UUID()
    private let makeRealtime: @MainActor (HAConnection, any HAWebsocketDelegate) -> any HARealtimeConnecting
    private var activeConnection: HAConnection?
    private var connectionGeneration = UUID()
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var stateRevision: UInt64 = 0
    private var entityRevisions: [String: UInt64] = [:]
    private(set) var lastUpdated: Date?
    private let actionPollDelay: Duration
    let startRealtimeOnRefresh: Bool

    init(
        config: AppConfig,
        startRealtimeOnRefresh: Bool = true,
        actionPollDelay: Duration = .milliseconds(300),
        makeRealtime: @escaping @MainActor (HAConnection, any HAWebsocketDelegate) -> any HARealtimeConnecting = {
            HomeAssistantWebSocket(baseURL: $0.baseURL, token: $0.token, delegate: $1)
        },
        makeClient: @escaping @MainActor (HAConnection) -> any HomeAssistantCalling = { HomeAssistantClient(connection: $0) }
    ) {
        self.config = config
        self.startRealtimeOnRefresh = startRealtimeOnRefresh
        self.makeClient = makeClient
        self.makeRealtime = makeRealtime
        self.actionPollDelay = actionPollDelay
        self.activeConnection = config.connection
        self.favorites = config.favorites
        self.entityAliases = config.entityAliases
        self.entityIcons = config.entityIcons
        self.menuBarSensors = config.menuBarSensors
        self.showsAppIconInMenuBar = config.showsAppIconInMenuBar
        refreshStatus()
    }

    // MARK: - Derived views

    var favoriteRows: [HAEntity] {
        favorites.entityIDs.compactMap { entities[$0] }
    }

    var menuBarSensorRows: [MenuBarSensorRow] {
        menuBarSensors.items.compactMap { item in
            guard let entity = entities[item.entityID] else { return nil }
            return MenuBarSensorRow(item: item, entity: entity)
        }
    }

    var missingFavoriteIDs: [String] {
        guard lastUpdated != nil else { return [] }
        return favorites.entityIDs.filter { entities[$0] == nil }
    }

    var missingMenuBarSensorIDs: [String] {
        guard lastUpdated != nil else { return [] }
        return menuBarSensors.items.map(\.entityID).filter { entities[$0] == nil }
    }

    func testConnection(_ connection: HAConnection) async throws {
        try await makeClient(connection).testConnection()
    }

    var sensorEntitiesSorted: [HAEntity] {
        allEntitiesSorted.filter(Self.isSensor)
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

    func addMenuBarSensor(_ entityID: String) {
        menuBarSensors.add(entityID)
        config.menuBarSensors = menuBarSensors
    }

    func removeMenuBarSensor(_ entityID: String) {
        menuBarSensors.remove(entityID)
        config.menuBarSensors = menuBarSensors
    }

    func menuBarSensorItem(for entityID: String) -> MenuBarSensorItem? {
        menuBarSensors.item(for: entityID)
    }

    func setMenuBarSensorIconName(_ iconName: String, for entityID: String) {
        menuBarSensors.setIconName(iconName, for: entityID)
        config.menuBarSensors = menuBarSensors
    }

    func setMenuBarSensorShowsIcon(_ showsIcon: Bool, for entityID: String) {
        menuBarSensors.setShowsIcon(showsIcon, for: entityID)
        config.menuBarSensors = menuBarSensors
    }

    func moveMenuBarSensor(_ entityID: String, to index: Int) {
        menuBarSensors.move(entityID, to: index)
        config.menuBarSensors = menuBarSensors
    }

    func moveMenuBarSensorsSubset(_ entityIDs: [String], from source: IndexSet, to destination: Int) {
        menuBarSensors.moveSubset(entityIDs, from: source, to: destination)
        config.menuBarSensors = menuBarSensors
    }

    func setShowsAppIconInMenuBar(_ showsIcon: Bool) {
        showsAppIconInMenuBar = showsIcon
        config.showsAppIconInMenuBar = showsIcon
    }

    // MARK: - Loading

    /// Coalesces concurrent callers and preserves newer realtime changes during a snapshot fetch.
    func refresh() async {
        synchronizeConnection()
        guard let connection = activeConnection else {
            status = .unconfigured
            return
        }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let operationID = UUID()
        let generation = connectionGeneration
        refreshID = operationID
        isLoading = true
        if entities.isEmpty { status = .connecting }
        let task = Task { await performRefresh(connection: connection, generation: generation, operationID: operationID) }
        refreshTask = task
        await task.value
    }

    private func performRefresh(connection: HAConnection, generation: UUID, operationID: UUID) async {
        defer {
            if refreshID == operationID {
                refreshTask = nil
                refreshID = nil
                isLoading = false
            }
        }
        let revision = stateRevision
        do {
            let states = try await makeClient(connection).fetchStates()
            guard isCurrent(generation, connection: connection), !Task.isCancelled else { return }
            var cache: [String: HAEntity] = [:]
            for entity in states { cache[entity.entityID] = entity }
            for (id, version) in entityRevisions where version > revision {
                cache[id] = entities[id]
            }
            entities = cache
            lastUpdated = Date()
            lastError = nil
            status = .connected
            await startRealtimeIfNeeded(connection: connection, generation: generation)
        } catch {
            guard isCurrent(generation, connection: connection) else { return }
            if Task.isCancelled || error is CancellationError {
                status = entities.isEmpty ? .disconnected : .connected
                return
            }
            let failure = (error as? HAError) ?? .transport(error.localizedDescription)
            lastError = failure
            status = .error(failure)
        }
    }

    /// View appearances share the cache; the refresh button explicitly requests a new snapshot.
    func refreshIfConfigured() async {
        synchronizeConnection()
        guard activeConnection != nil, lastUpdated == nil else { return }
        await refresh()
    }

    private func isCurrent(_ generation: UUID, connection: HAConnection) -> Bool {
        generation == connectionGeneration && activeConnection == connection && config.connection == connection
    }

    private func synchronizeConnection() {
        let connection = config.connection
        guard connection != activeConnection else { return }
        connectionGeneration = UUID()
        activeConnection = connection
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        isLoading = false
        stopRealtime()
        entities = [:]
        entityRevisions = [:]
        pendingActions = []
        actionIDs = [:]
        actionServices = [:]
        actionErrors = [:]
        lastError = nil
        lastUpdated = nil
        status = connection == nil ? .unconfigured : .disconnected
    }

    // MARK: - Service calls

    func callService(domain: String, service: String, entityID: String, serviceData: [String: Any]? = nil) async {
        synchronizeConnection()
        let interruptsCover = domain == "cover" && service == "stop_cover" && actionServices[entityID] != "stop_cover"
        guard !pendingActions.contains(entityID) || interruptsCover else { return }
        guard let connection = activeConnection else {
            actionErrors[entityID] = .missingToken
            return
        }
        let generation = connectionGeneration
        let client = makeClient(connection)
        let actionID = UUID()
        actionIDs[entityID] = actionID
        actionServices[entityID] = service
        pendingActions.insert(entityID)
        actionErrors[entityID] = nil
        let previous = entities[entityID]
        defer {
            if isCurrent(generation, connection: connection), actionIDs[entityID] == actionID {
                pendingActions.remove(entityID)
                actionIDs[entityID] = nil
                actionServices[entityID] = nil
            }
        }
        do {
            try await client.callService(domain: domain, service: service, entityID: entityID, serviceData: serviceData)
            guard isCurrent(generation, connection: connection), actionIDs[entityID] == actionID, !Task.isCancelled else { return }
            await pollForStateChange(client: client, entityID: entityID, previous: previous,
                                     connection: connection, generation: generation, actionID: actionID)
        } catch {
            guard isCurrent(generation, connection: connection), actionIDs[entityID] == actionID, !Task.isCancelled, !(error is CancellationError) else { return }
            actionErrors[entityID] = (error as? HAError) ?? .transport(error.localizedDescription)
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
        let range = entities[entityID]?.colorTempRange ?? 1...40_000
        let clamped = min(max(kelvin, range.lowerBound), range.upperBound)
        await callService(domain: "light", service: "turn_on", entityID: entityID, serviceData: ["color_temp_kelvin": clamped])
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
        guard temperature.isFinite else { return }
        let value: Double
        if let entity = entities[entityID], let range = entity.climateTemperatureRange {
            value = SliderValueScale.quantized(temperature, range: range, step: entity.climateTemperatureStep)
        } else { value = temperature }
        await callService(
            domain: "climate",
            service: "set_temperature",
            entityID: entityID,
            serviceData: ["temperature": value]
        )
    }

    // MARK: - Favorites

    /// Attribute changes count too: brightness/temperature may change while state stays "on".
    private func pollForStateChange(
        client: any HomeAssistantCalling,
        entityID: String,
        previous: HAEntity?,
        connection: HAConnection,
        generation: UUID,
        actionID: UUID
    ) async {
        var delay = actionPollDelay
        for _ in 0..<6 {
            guard isCurrent(generation, connection: connection), actionIDs[entityID] == actionID, !Task.isCancelled else { return }
            if let current = entities[entityID], hasChanged(current, from: previous) { return }
            do {
                try await Task.sleep(for: delay)
                let revision = stateRevision
                let updated = try await client.fetchEntity(entityID: entityID)
                guard isCurrent(generation, connection: connection), actionIDs[entityID] == actionID, !Task.isCancelled else { return }
                // A realtime update received during this request takes precedence over its response.
                if (entityRevisions[entityID] ?? 0) <= revision {
                    entities[entityID] = updated
                    recordChange(entityID)
                }
                if let current = entities[entityID], hasChanged(current, from: previous) { return }
            } catch { return }
            delay = min(delay * 2, .milliseconds(1500))
        }
    }

    private func hasChanged(_ entity: HAEntity, from previous: HAEntity?) -> Bool {
        entity.state != previous?.state || entity.attributes != previous?.attributes
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
        menuBarSensors = config.menuBarSensors
        showsAppIconInMenuBar = config.showsAppIconInMenuBar
        synchronizeConnection()
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

    private static func isSensor(_ entity: HAEntity) -> Bool {
        entity.domain == HADomain.sensor.rawValue || entity.domain == HADomain.binarySensor.rawValue
    }

    // MARK: - WebSocket

    private func startRealtimeIfNeeded(connection: HAConnection, generation: UUID) async {
        guard startRealtimeOnRefresh, isCurrent(generation, connection: connection) else { return }
        if let webSocket {
            if case .failed = realtimeStatus { await webSocket.start() }
            return
        }
        realtimeGeneration = UUID()
        let sink = HARealtimeSink(store: self, generation: realtimeGeneration)
        realtimeSink = sink
        let socket = makeRealtime(connection, sink)
        webSocket = socket
        await socket.start()
    }

    func stopRealtime() {
        realtimeGeneration = UUID()
        realtimeSink = nil
        if let socket = webSocket { Task { await socket.stop() } }
        webSocket = nil
        realtimeStatus = .disconnected
    }

    fileprivate func receive(status: HARealtimeStatus, generation: UUID) {
        guard generation == realtimeGeneration, realtimeSink != nil, config.connection == activeConnection else { return }
        realtimeStatus = status
        if status == .connected {
            // Catch events missed before subscription and during a reconnect gap.
            Task {
                if let refreshTask { await refreshTask.value }
                guard generation == realtimeGeneration, realtimeSink != nil, config.connection == activeConnection else { return }
                await refresh()
            }
        }
    }

    fileprivate func receive(event: HAWebsocketEvent, generation: UUID) {
        guard generation == realtimeGeneration, realtimeSink != nil, config.connection == activeConnection else { return }
        applyRealtimeEvent(event)
    }

    func realtime(didChange status: HARealtimeStatus) {
        realtimeStatus = status
    }

    func realtime(didReceive event: HAWebsocketEvent) {
        applyRealtimeEvent(event)
    }

    private func applyRealtimeEvent(_ event: HAWebsocketEvent) {
        let entityID: String
        switch event {
        case .stateChanged(let id, let entity):
            entityID = id
            entities[id] = entity
        case .entityRemoved(let id):
            entityID = id
            entities[id] = nil
        case .unknown:
            return
        }
        recordChange(entityID)
    }

    private func recordChange(_ entityID: String) {
        stateRevision += 1
        entityRevisions[entityID] = stateRevision
        lastUpdated = Date()
    }
}

@MainActor
private final class HARealtimeSink: HAWebsocketDelegate {
    weak var store: HomeAssistantStore?
    let generation: UUID

    init(store: HomeAssistantStore, generation: UUID) {
        self.store = store
        self.generation = generation
    }

    func realtime(didChange status: HARealtimeStatus) {
        store?.receive(status: status, generation: generation)
    }

    func realtime(didReceive event: HAWebsocketEvent) {
        store?.receive(event: event, generation: generation)
    }
}
