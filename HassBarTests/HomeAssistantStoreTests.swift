import XCTest
@testable import HassBar

@MainActor
final class FakeHAClient: HomeAssistantCalling {
    var fetchResult: Result<[HAEntity], Error>
    var callResult: Result<Void, Error> = .success(())
    var testResult: Result<Void, Error> = .success(())
    var fetchEntityResult: Result<HAEntity, Error>?
    private(set) var callInvocations: [(domain: String, service: String, entityID: String, serviceData: [String: Any]?)] = []
    var fetchHandler: (() async throws -> [HAEntity])?
    var callHandler: (() async throws -> Void)?
    private(set) var fetchCount = 0
    private(set) var fetchEntityInvocations: [String] = []

    init(fetchResult: Result<[HAEntity], Error> = .success([])) {
        self.fetchResult = fetchResult
    }

    func testConnection() async throws {
        try testResult.get()
    }

    func fetchStates() async throws -> [HAEntity] {
        fetchCount += 1
        if let fetchHandler { return try await fetchHandler() }
        return try fetchResult.get()
    }

    func fetchEntity(entityID: String) async throws -> HAEntity {
        fetchEntityInvocations.append(entityID)
        if let result = fetchEntityResult {
            return try result.get()
        }
        guard let entity = try fetchResult.get().first(where: { $0.entityID == entityID }) else { throw HAError.httpStatus(404) }
        return entity
    }

    func callService(domain: String, service: String, entityID: String, serviceData: [String: Any]?) async throws {
        callInvocations.append((domain, service, entityID, serviceData))
        if let callHandler { try await callHandler() }
        try callResult.get()
    }
}

@MainActor
final class FakeHARealtime: HARealtimeConnecting {
    let delegate: any HAWebsocketDelegate
    private(set) var starts = 0
    private(set) var stops = 0

    init(delegate: any HAWebsocketDelegate) { self.delegate = delegate }
    @MainActor func start() async { starts += 1 }
    @MainActor func stop() async { stops += 1 }
}

@MainActor
final class HomeAssistantStoreTests: XCTestCase {
    private func entity(_ id: String, _ state: String) -> HAEntity {
        HAEntity(entityID: id, state: state, attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil))
    }

    private func configuredStore(fetch: Result<[HAEntity], Error> = .success([])) -> (HomeAssistantStore, FakeHAClient) {
        let config = TestSupport.makeConfig()
        config.haURL = "http://ha.local:8123"
        try? config.saveToken("T")
        let fake = FakeHAClient(fetchResult: fetch)
        let store = HomeAssistantStore(config: config, startRealtimeOnRefresh: false, actionPollDelay: .zero, makeClient: { _ in fake })
        return (store, fake)
    }

    func testConcurrentRefreshesShareOneRequestAndAppearanceUsesCache() async {
        let (store, fake) = configuredStore()
        var resume: CheckedContinuation<[HAEntity], Error>?
        fake.fetchHandler = { try await withCheckedThrowingContinuation { resume = $0 } }
        let first = Task { await store.refresh() }
        while resume == nil { await Task.yield() }
        let second = Task { await store.refresh() }
        await Task.yield()
        resume?.resume(returning: [entity("light.a", "on")])
        await first.value
        await second.value
        await store.refreshIfConfigured()
        XCTAssertEqual(fake.fetchCount, 1)
        XCTAssertFalse(store.isLoading)
    }

    func testOldServerResponseCannotReplaceNewServerCache() async throws {
        let (store, fake) = configuredStore()
        var resume: CheckedContinuation<[HAEntity], Error>?
        fake.fetchHandler = { try await withCheckedThrowingContinuation { resume = $0 } }
        let oldRequest = Task { await store.refresh() }
        while resume == nil { await Task.yield() }
        try store.config.saveConnection(url: "http://new.local", token: "NEW")
        store.reloadConfiguration()
        XCTAssertTrue(store.entities.isEmpty)
        XCTAssertFalse(store.isLoading)
        fake.fetchHandler = nil
        fake.fetchResult = .success([entity("sensor.new", "42")])
        await store.refresh()
        resume?.resume(returning: [entity("sensor.old", "1")])
        await oldRequest.value
        XCTAssertEqual(Set(store.entities.keys), ["sensor.new"])
        XCTAssertEqual(store.status, .connected)
    }

    func testSnapshotDoesNotOverwriteNewerRealtimeChangesOrDeletion() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "off"), entity("sensor.old", "1")]))
        await store.refresh()
        var resume: CheckedContinuation<[HAEntity], Error>?
        fake.fetchHandler = { try await withCheckedThrowingContinuation { resume = $0 } }
        let request = Task { await store.refresh() }
        while resume == nil { await Task.yield() }
        store.realtime(didReceive: .stateChanged(entityID: "light.a", entity: entity("light.a", "on")))
        store.realtime(didReceive: .entityRemoved(entityID: "sensor.old"))
        resume?.resume(returning: [entity("light.a", "off"), entity("sensor.old", "1")])
        await request.value
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
        XCTAssertNil(store.entities["sensor.old"])
    }

    func testDuplicateActionsAreIgnoredUntilServiceReturns() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "off")]))
        await store.refresh()
        var resume: CheckedContinuation<Void, Error>?
        fake.callHandler = { try await withCheckedThrowingContinuation { resume = $0 } }
        let action = Task { await store.callService(domain: "light", service: "turn_on", entityID: "light.a") }
        while resume == nil { await Task.yield() }
        store.realtime(didReceive: .stateChanged(entityID: "light.a", entity: entity("light.a", "on")))
        XCTAssertTrue(store.pendingActions.contains("light.a"))
        await store.callService(domain: "light", service: "turn_on", entityID: "light.a")
        XCTAssertEqual(fake.callInvocations.count, 1)
        resume?.resume(returning: ())
        await action.value
        XCTAssertFalse(store.pendingActions.contains("light.a"))
    }

    func testCoverStopCanInterruptPendingOpenWithoutOldActionWritingBack() async {
        let (store, fake) = configuredStore(fetch: .success([entity("cover.a", "closed")]))
        await store.refresh()
        var resume: CheckedContinuation<Void, Error>?
        fake.callHandler = {
            if fake.callInvocations.count == 1 {
                try await withCheckedThrowingContinuation { resume = $0 }
            }
        }
        let opening = Task { await store.callService(domain: "cover", service: "open_cover", entityID: "cover.a") }
        while resume == nil { await Task.yield() }
        await store.callService(domain: "cover", service: "stop_cover", entityID: "cover.a")
        XCTAssertEqual(fake.callInvocations.map(\.service), ["open_cover", "stop_cover"])
        XCTAssertFalse(store.pendingActions.contains("cover.a"))
        resume?.resume(throwing: HAError.httpStatus(500))
        await opening.value
        XCTAssertNil(store.actionErrors["cover.a"])
    }

    func testAttributeOnlyChangeEndsActionPolling() async {
        let before = HAEntity(entityID: "light.a", state: "on", attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil, brightness: 10))
        let after = HAEntity(entityID: "light.a", state: "on", attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil, brightness: 128))
        let (store, fake) = configuredStore(fetch: .success([before]))
        fake.fetchEntityResult = .success(after)
        await store.refresh()
        await store.setBrightness(entityID: "light.a", percent: 50)
        XCTAssertEqual(fake.fetchEntityInvocations.count, 1)
        XCTAssertEqual(store.entities["light.a"]?.brightnessPercent, 50)
    }

    func testRefreshFailureRetainsLastKnownCache() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "on")]))
        await store.refresh()
        fake.fetchResult = .failure(HAError.httpStatus(503))
        await store.refresh()
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertEqual(store.lastError, .httpStatus(503))
    }

    func testMissingSelectionsRemainManageableAndConnectionTestUsesInjectedClient() async {
        let (store, fake) = configuredStore(fetch: .success([entity("sensor.present", "21")]))
        store.config.favorites = Favorites(entityIDs: ["sensor.present", "light.removed"])
        store.config.menuBarSensors = MenuBarSensors(items: [MenuBarSensorItem(entityID: "sensor.removed")])
        store.reloadConfiguration()
        XCTAssertTrue(store.missingFavoriteIDs.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.missingFavoriteIDs, ["light.removed"])
        XCTAssertEqual(store.missingMenuBarSensorIDs, ["sensor.removed"])
        fake.testResult = .failure(HAError.httpStatus(401))
        do {
            try await store.testConnection(store.config.connection!)
            XCTFail("Injected connection failure should be surfaced")
        } catch {
            XCTAssertEqual(error as? HAError, .httpStatus(401))
        }
        store.toggleFavorite("light.removed")
        store.removeMenuBarSensor("sensor.removed")
        XCTAssertTrue(store.missingFavoriteIDs.isEmpty)
        XCTAssertTrue(store.missingMenuBarSensorIDs.isEmpty)
    }

    func testRefreshKeepsSocketAndIgnoresCallbacksFromReplacedConnection() async throws {
        let config = TestSupport.makeConfig()
        try config.saveConnection(url: "http://old.local", token: "OLD")
        let fake = FakeHAClient(fetchResult: .success([entity("light.a", "off")]))
        var sockets: [FakeHARealtime] = []
        let store = HomeAssistantStore(config: config, makeRealtime: { _, delegate in
            let socket = FakeHARealtime(delegate: delegate)
            sockets.append(socket)
            return socket
        }, makeClient: { _ in fake })
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(sockets.count, 1)
        XCTAssertEqual(sockets[0].starts, 1)
        try config.saveConnection(url: "http://new.local", token: "NEW")
        store.reloadConfiguration()
        await store.refresh()
        XCTAssertEqual(sockets.count, 2)
        sockets[0].delegate.realtime(didChange: .failed("Old failure"))
        sockets[0].delegate.realtime(didReceive: .stateChanged(entityID: "sensor.old", entity: entity("sensor.old", "1")))
        XCTAssertNil(store.entities["sensor.old"])
        XCTAssertEqual(store.realtimeStatus, .disconnected)
        store.stopRealtime()
    }

    func testSubscriptionAndReconnectResynchronizeSnapshot() async throws {
        let config = TestSupport.makeConfig()
        try config.saveConnection(url: "http://ha.local", token: "T")
        let fake = FakeHAClient(fetchResult: .success([entity("light.a", "off")]))
        var socket: FakeHARealtime?
        let store = HomeAssistantStore(config: config, makeRealtime: { _, delegate in
            let result = FakeHARealtime(delegate: delegate)
            socket = result
            return result
        }, makeClient: { _ in fake })
        await store.refresh()
        fake.fetchResult = .success([entity("light.a", "on")])
        socket?.delegate.realtime(didChange: .connected)
        while fake.fetchCount < 2 || store.isLoading { await Task.yield() }
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
        XCTAssertEqual(socket?.starts, 1)
        store.stopRealtime()
    }

    func testRefreshPopulatesCacheAndConnected() async {
        let (store, _) = configuredStore(fetch: .success([entity("light.a","on"), entity("switch.b","off")]))
        await store.refresh()
        XCTAssertEqual(store.entities.count, 2)
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
        XCTAssertEqual(store.status, .connected)
        XCTAssertFalse(store.isLoading)
    }

    func testRefreshErrorKeepsErrorState() async {
        let (store, _) = configuredStore(fetch: .failure(HAError.httpStatus(500)))
        await store.refresh()
        XCTAssertEqual(store.status, .error(.httpStatus(500)))
        XCTAssertEqual(store.lastError, .httpStatus(500))
        XCTAssertTrue(store.entities.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testFavoriteRowsRespectOrderingAndMissing() async {
        let (store, _) = configuredStore(fetch: .success([entity("light.a","on"), entity("switch.b","off"), entity("sensor.c","22")]))
        store.config.favorites = Favorites(entityIDs: ["switch.b", "light.a", "missing.id"])
        store.reloadConfiguration()
        await store.refresh()
        XCTAssertEqual(store.favoriteRows.map(\.id), ["switch.b", "light.a"])
    }

    func testToggleFavoriteWritesBack() {
        let (store, _) = configuredStore()
        store.toggleFavorite("light.a")
        XCTAssertEqual(store.favorites.entityIDs, ["light.a"])
        XCTAssertEqual(store.config.favorites.entityIDs, ["light.a"])
        store.toggleFavorite("light.a")
        XCTAssertTrue(store.favorites.entityIDs.isEmpty)
    }

    func testCallServiceRecordsAndClearsPending() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a","off")]))
        fake.fetchEntityResult = .success(entity("light.a","on"))
        await store.refresh()
        await store.callService(domain: "light", service: "turn_on", entityID: "light.a")
        XCTAssertEqual(
            fake.callInvocations.map { "\($0.domain)|\($0.service)|\($0.entityID)|\($0.serviceData ?? [:])" },
            ["light|turn_on|light.a|[:]"]
        )
        XCTAssertTrue(store.pendingActions.isEmpty)
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
    }

    func testCallServiceFailureSetsRowError() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a","off")]))
        fake.callResult = .failure(HAError.httpStatus(503))
        await store.refresh()
        await store.callService(domain: "light", service: "turn_on", entityID: "light.a")
        XCTAssertEqual(store.actionErrors["light.a"], .httpStatus(503))
        XCTAssertTrue(store.pendingActions.isEmpty)
    }

    func testRealtimeEventUpdatesSingleEntity() async {
        let (store, _) = configuredStore(fetch: .success([entity("light.a","off")]))
        await store.refresh()
        let updated = HAEntity(entityID: "light.a", state: "on", attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil))
        store.realtime(didReceive: .stateChanged(entityID: "light.a", entity: updated))
        await Task.yield()
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
    }

    func testUnconfiguredRefreshStaysUnconfigured() async {
        let config = TestSupport.makeConfig()
        let store = HomeAssistantStore(config: config)
        await store.refresh()
        XCTAssertEqual(store.status, .unconfigured)
    }

    func testSetBrightnessTurnsOnWithBrightness() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "off")]))
        await store.refresh()
        await store.setBrightness(entityID: "light.a", percent: 50)
        XCTAssertEqual(fake.callInvocations.count, 1)
        XCTAssertEqual(fake.callInvocations[0].domain, "light")
        XCTAssertEqual(fake.callInvocations[0].service, "turn_on")
        XCTAssertEqual(fake.callInvocations[0].entityID, "light.a")
        XCTAssertEqual(fake.callInvocations[0].serviceData?["brightness"] as? Int, 128)
    }

    func testSetBrightnessToZeroTurnsOff() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "on")]))
        await store.refresh()
        await store.setBrightness(entityID: "light.a", percent: 0)
        XCTAssertEqual(fake.callInvocations.count, 1)
        XCTAssertEqual(fake.callInvocations[0].service, "turn_off")
    }

    func testSetColorTemperatureSendsKelvin() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a", "on")]))
        await store.refresh()
        await store.setColorTemperature(entityID: "light.a", kelvin: 3500)
        XCTAssertEqual(fake.callInvocations.count, 1)
        XCTAssertEqual(fake.callInvocations[0].service, "turn_on")
        XCTAssertEqual(fake.callInvocations[0].serviceData?["color_temp_kelvin"] as? Int, 3500)
    }

    func testSetClimateHVACModeSendsMode() async {
        let (store, fake) = configuredStore(fetch: .success([entity("climate.a", "off")]))
        await store.refresh()
        await store.setClimateHVACMode(entityID: "climate.a", mode: "cool")
        XCTAssertEqual(fake.callInvocations.count, 1)
        XCTAssertEqual(fake.callInvocations[0].domain, "climate")
        XCTAssertEqual(fake.callInvocations[0].service, "set_hvac_mode")
        XCTAssertEqual(fake.callInvocations[0].serviceData?["hvac_mode"] as? String, "cool")
    }

    func testSetClimateTemperatureSendsTemperature() async {
        let (store, fake) = configuredStore(fetch: .success([entity("climate.a", "cool")]))
        await store.refresh()
        await store.setClimateTemperature(entityID: "climate.a", temperature: 24.5)
        XCTAssertEqual(fake.callInvocations.count, 1)
        XCTAssertEqual(fake.callInvocations[0].domain, "climate")
        XCTAssertEqual(fake.callInvocations[0].service, "set_temperature")
        XCTAssertEqual(fake.callInvocations[0].serviceData?["temperature"] as? Double, 24.5)
    }

    func testCustomIconMethods() {
        let (store, _) = configuredStore()
        XCTAssertEqual(store.customIcon(for: "light.living_room"), "")
        
        store.setCustomIcon("sparkles", for: "light.living_room")
        XCTAssertEqual(store.customIcon(for: "light.living_room"), "sparkles")
        XCTAssertEqual(store.config.entityIcons.icon(for: "light.living_room"), "sparkles")
    }

    func testMenuBarSensorRowsRespectOrderingAndMissing() async {
        let (store, _) = configuredStore(fetch: .success([
            entity("sensor.temperature", "22"),
            entity("binary_sensor.motion", "off"),
            entity("light.a", "on")
        ]))
        store.config.menuBarSensors = MenuBarSensors(items: [
            MenuBarSensorItem(entityID: "binary_sensor.motion", iconName: "figure.walk", showsIcon: false),
            MenuBarSensorItem(entityID: "missing.id"),
            MenuBarSensorItem(entityID: "sensor.temperature", iconName: "thermometer.medium", showsIcon: true)
        ])
        store.reloadConfiguration()

        await store.refresh()

        XCTAssertEqual(store.menuBarSensorRows.map(\.id), ["binary_sensor.motion", "sensor.temperature"])
        XCTAssertEqual(store.menuBarSensorRows.first?.item.showsIcon, false)
        XCTAssertEqual(store.menuBarSensorRows.last?.item.iconName, "thermometer.medium")
    }

    func testMenuBarSensorMethodsWriteBack() {
        let (store, _) = configuredStore()

        store.addMenuBarSensor("sensor.temperature")
        store.setMenuBarSensorIconName("thermometer.medium", for: "sensor.temperature")
        store.setMenuBarSensorShowsIcon(false, for: "sensor.temperature")

        XCTAssertEqual(store.menuBarSensors.items.map(\.entityID), ["sensor.temperature"])
        XCTAssertEqual(store.config.menuBarSensors.item(for: "sensor.temperature")?.iconName, "thermometer.medium")
        XCTAssertEqual(store.config.menuBarSensors.item(for: "sensor.temperature")?.showsIcon, false)

        store.removeMenuBarSensor("sensor.temperature")
        XCTAssertTrue(store.config.menuBarSensors.items.isEmpty)
    }

    func testShowsAppIconInMenuBarWritesBack() {
        let (store, _) = configuredStore()
        XCTAssertTrue(store.showsAppIconInMenuBar)

        store.setShowsAppIconInMenuBar(false)

        XCTAssertFalse(store.showsAppIconInMenuBar)
        XCTAssertFalse(store.config.showsAppIconInMenuBar)

        store.config.showsAppIconInMenuBar = true
        store.reloadConfiguration()

        XCTAssertTrue(store.showsAppIconInMenuBar)
    }

    func testMenuBarSensorMoveWritesBack() {
        let (store, _) = configuredStore()
        store.config.menuBarSensors = MenuBarSensors(items: [
            MenuBarSensorItem(entityID: "sensor.a"),
            MenuBarSensorItem(entityID: "sensor.b"),
            MenuBarSensorItem(entityID: "sensor.c")
        ])
        store.reloadConfiguration()

        store.moveMenuBarSensor("sensor.c", to: 0)

        XCTAssertEqual(store.menuBarSensors.items.map(\.entityID), ["sensor.c", "sensor.a", "sensor.b"])
        XCTAssertEqual(store.config.menuBarSensors.items.map(\.entityID), ["sensor.c", "sensor.a", "sensor.b"])
    }
}
