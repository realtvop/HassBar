import XCTest
@testable import HassBar

final class EntityActionMappingTests: XCTestCase {
    private func entity(_ id: String, state: String) -> HAEntity {
        HAEntity(entityID: id, state: state, attributes: HAAttributes(friendlyName: nil, unitOfMeasurement: nil))
    }

    func testSwitchActionsFull() {
        let acts = EntityActionMapping.actions(for: entity("switch.x", state: "off"))
        let services = acts.map(\.service)
        XCTAssertEqual(services, ["turn_on", "turn_off", "toggle"])
    }

    func testLightDisplayOnShowsTurnOff() {
        let acts = EntityActionMapping.displayActions(for: entity("light.k", state: "on"))
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0].service, "turn_off")
        XCTAssertEqual(acts[0].title, "Turn Off")
    }

    func testLightDisplayOffShowsTurnOn() {
        let acts = EntityActionMapping.displayActions(for: entity("light.k", state: "off"))
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0].service, "turn_on")
    }

    func testCoverOpenShowsCloseAndStop() {
        let acts = EntityActionMapping.displayActions(for: entity("cover.garage", state: "open"))
        XCTAssertEqual(acts.map(\.service), ["close_cover", "stop_cover"])
    }

    func testCoverClosedShowsOpenAndStop() {
        let acts = EntityActionMapping.displayActions(for: entity("cover.garage", state: "closed"))
        XCTAssertEqual(acts.map(\.service), ["open_cover", "stop_cover"])
    }

    func testClimateDisplayOnShowsTurnOff() {
        let acts = EntityActionMapping.displayActions(for: entity("climate.living_room", state: "cool"))
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0].domain, "climate")
        XCTAssertEqual(acts[0].service, "turn_off")
        XCTAssertEqual(acts[0].title, "Turn Off")
    }

    func testClimateDisplayOffShowsTurnOn() {
        let acts = EntityActionMapping.displayActions(for: entity("climate.living_room", state: "off"))
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0].service, "turn_on")
    }

    func testLockLockedShowsUnlock() {
        let acts = EntityActionMapping.displayActions(for: entity("lock.door", state: "locked"))
        XCTAssertEqual(acts.map(\.service), ["unlock"])
    }

    func testLockUnlockedShowsLock() {
        let acts = EntityActionMapping.displayActions(for: entity("lock.door", state: "unlocked"))
        XCTAssertEqual(acts.map(\.service), ["lock"])
    }

    func testSceneAndScriptShowRun() {
        XCTAssertEqual(EntityActionMapping.displayActions(for: entity("scene.movie", state: "unknown")).map(\.service), ["turn_on"])
        XCTAssertEqual(EntityActionMapping.displayActions(for: entity("script.goodnight", state: "unknown")).map(\.service), ["turn_on"])
    }

    func testSensorsAreReadOnly() {
        XCTAssertTrue(EntityActionMapping.displayActions(for: entity("sensor.temp", state: "21")).isEmpty)
        XCTAssertTrue(EntityActionMapping.displayActions(for: entity("binary_sensor.motion", state: "on")).isEmpty)
    }

    func testUnknownDomainIsReadOnly() {
        XCTAssertTrue(EntityActionMapping.displayActions(for: entity("vacuum.cleaner", state: "cleaning")).isEmpty)
    }
}
