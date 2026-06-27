import XCTest
@testable import HassBar

@MainActor
final class FakeHAClient: HomeAssistantCalling {
    var fetchResult: Result<[HAEntity], Error>
    var callResult: Result<Void, Error> = .success(())
    var testResult: Result<Void, Error> = .success(())
    private(set) var callInvocations: [(domain: String, service: String, entityID: String)] = []
    private(set) var fetchCount = 0

    init(fetchResult: Result<[HAEntity], Error> = .success([])) {
        self.fetchResult = fetchResult
    }

    func testConnection() async throws {
        try testResult.get()
    }

    func fetchStates() async throws -> [HAEntity] {
        fetchCount += 1
        return try fetchResult.get()
    }

    func callService(domain: String, service: String, entityID: String) async throws {
        callInvocations.append((domain, service, entityID))
        try callResult.get()
    }
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
        let store = HomeAssistantStore(config: config, startRealtimeOnRefresh: false) { _ in fake }
        return (store, fake)
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
        await store.refresh()
        await store.callService(domain: "light", service: "turn_on", entityID: "light.a")
        XCTAssertEqual(
            fake.callInvocations.map { "\($0.domain)|\($0.service)|\($0.entityID)" },
            ["light|turn_on|light.a"]
        )
        XCTAssertTrue(store.pendingActions.isEmpty)
    }

    func testCallServiceFailureSetsRowError() async {
        let (store, fake) = configuredStore(fetch: .success([entity("light.a","off")]))
        fake.callResult = .failure(HAError.httpStatus(503))
        await store.refresh()
        await store.callService(domain: "light", service: "turn_on", entityID: "light.a")
        XCTAssertEqual(store.actionErrors["light.a"], .httpStatus(503))
        XCTAssertTrue(store.pendingActions.isEmpty)
    }

    func testApplyRealtimeEventUpdatesSingleEntityAndClearsPending() async {
        let (store, _) = configuredStore(fetch: .success([entity("light.a","off")]))
        await store.refresh()
        store.registerPendingAction("light.a")
        let updated = HAEntity(entityID: "light.a", state: "on", attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil))
        store.realtime(didReceive: .stateChanged(entityID: "light.a", entity: updated))
        await Task.yield()
        XCTAssertEqual(store.entities["light.a"]?.state, "on")
        XCTAssertFalse(store.pendingActions.contains("light.a"))
    }

    func testUnconfiguredRefreshStaysUnconfigured() async {
        let config = TestSupport.makeConfig()
        let store = HomeAssistantStore(config: config)
        await store.refresh()
        XCTAssertEqual(store.status, .unconfigured)
    }
}