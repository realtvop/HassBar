import XCTest
@testable import HassBar

final class FavoritesTests: XCTestCase {
    func testAddAppendOnly() {
        var f = Favorites()
        f.add("a"); f.add("b"); f.add("a")
        XCTAssertEqual(f.entityIDs, ["a", "b"])
    }

    func testToggle() {
        var f = Favorites(entityIDs: ["a"])
        XCTAssertTrue(f.toggle("b"))
        XCTAssertEqual(f.entityIDs, ["a", "b"])
        XCTAssertFalse(f.toggle("a"))
        XCTAssertEqual(f.entityIDs, ["b"])
    }

    func testRemove() {
        var f = Favorites(entityIDs: ["a", "b"])
        f.remove("a")
        XCTAssertEqual(f.entityIDs, ["b"])
    }

    func testMoveToFront() {
        var f = Favorites(entityIDs: ["a", "b", "c"])
        f.move("c", to: 0)
        XCTAssertEqual(f.entityIDs, ["c", "a", "b"])
    }

    func testMoveToEnd() {
        var f = Favorites(entityIDs: ["a", "b", "c"])
        f.move("a", to: 3)
        XCTAssertEqual(f.entityIDs, ["b", "c", "a"])
    }

    func testMoveSamePosition() {
        var f = Favorites(entityIDs: ["a", "b"])
        f.move("a", to: 0)
        XCTAssertEqual(f.entityIDs, ["a", "b"])
    }

    func testRawRepresentableRoundTrip() {
        var f = Favorites(entityIDs: ["a", "b"])
        let raw = f.rawValue
        XCTAssertNotNil(Favorites(rawValue: raw))
        XCTAssertEqual(Favorites(rawValue: raw)?.entityIDs, ["a", "b"])
        XCTAssertNil(Favorites(rawValue: "not-json"))
        f.add("c")
        XCTAssertEqual(Favorites(rawValue: f.rawValue)?.entityIDs, ["a", "b", "c"])
    }

    func testEntityIcons() {
        var icons = EntityIcons()
        XCTAssertNil(icons.icon(for: "light.living_room"))
        
        icons.setIcon("lightbulb", for: "light.living_room")
        XCTAssertEqual(icons.icon(for: "light.living_room"), "lightbulb")
        
        icons.setIcon("  ", for: "light.living_room")
        XCTAssertNil(icons.icon(for: "light.living_room"))
    }

    func testEntityIconsRawRepresentable() {
        let icons = EntityIcons(iconsByEntityID: ["light.living_room": "lightbulb"])
        let raw = icons.rawValue
        let decoded = EntityIcons(rawValue: raw)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.icon(for: "light.living_room"), "lightbulb")
        XCTAssertNil(EntityIcons(rawValue: "invalid-json"))
    }

    func testMenuBarSensorsAddRemoveAndNoDuplicates() {
        var sensors = MenuBarSensors()
        sensors.add("sensor.temperature")
        sensors.add("binary_sensor.motion")
        sensors.add("sensor.temperature")

        XCTAssertEqual(sensors.items.map(\.entityID), ["sensor.temperature", "binary_sensor.motion"])

        sensors.remove("sensor.temperature")
        XCTAssertEqual(sensors.items.map(\.entityID), ["binary_sensor.motion"])
    }

    func testMenuBarSensorsIconSettingsTrimAndToggle() {
        var sensors = MenuBarSensors()
        sensors.add("sensor.temperature")

        sensors.setIconName("  thermometer.medium  ", for: "sensor.temperature")
        sensors.setShowsIcon(false, for: "sensor.temperature")

        XCTAssertEqual(sensors.item(for: "sensor.temperature")?.iconName, "thermometer.medium")
        XCTAssertEqual(sensors.item(for: "sensor.temperature")?.showsIcon, false)
    }

    func testMenuBarSensorsMove() {
        var sensors = MenuBarSensors(items: [
            MenuBarSensorItem(entityID: "sensor.a"),
            MenuBarSensorItem(entityID: "sensor.b"),
            MenuBarSensorItem(entityID: "sensor.c")
        ])

        sensors.move("sensor.c", to: 0)

        XCTAssertEqual(sensors.items.map(\.entityID), ["sensor.c", "sensor.a", "sensor.b"])
    }

    func testMenuBarSensorsRawRepresentable() {
        let sensors = MenuBarSensors(items: [
            MenuBarSensorItem(entityID: "sensor.temperature", iconName: "  thermometer.medium  ", showsIcon: true),
            MenuBarSensorItem(entityID: "binary_sensor.motion", iconName: "figure.walk", showsIcon: false)
        ])

        let raw = sensors.rawValue
        let decoded = MenuBarSensors(rawValue: raw)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.items, [
            MenuBarSensorItem(entityID: "sensor.temperature", iconName: "thermometer.medium", showsIcon: true),
            MenuBarSensorItem(entityID: "binary_sensor.motion", iconName: "figure.walk", showsIcon: false)
        ])
        XCTAssertNil(MenuBarSensors(rawValue: "not-json"))
    }
}
