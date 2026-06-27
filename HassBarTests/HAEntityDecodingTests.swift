import XCTest
@testable import HassBar

final class HAEntityDecodingTests: XCTestCase {
    func testDecodesBasicEntityAndHelpers() throws {
        let json = """
        {
            "entity_id": "light.living_room",
            "state": "on",
            "attributes": {"friendly_name": "Living Room", "unit_of_measurement": null},
            "last_changed": "2026-06-28T00:00:00Z"
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.id, "light.living_room")
        XCTAssertEqual(entity.domain, "light")
        XCTAssertEqual(entity.localID, "living_room")
        XCTAssertEqual(entity.friendlyName, "Living Room")
        XCTAssertEqual(entity.state, "on")
        XCTAssertTrue(entity.isAvailable)
        XCTAssertEqual(entity.displayState, "on")
    }

    func testDecodesUnitOfMeasurement() throws {
        let json = """
        {"entity_id":"sensor.temp","state":"21.5","attributes":{"unit_of_measurement":"°C"}}
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.displayState, "21.5 °C")
    }

    func testUnavailableStateTreatedAsUnavailable() throws {
        let json = """
        {"entity_id":"switch.plug","state":"unavailable","attributes":{}}
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertFalse(entity.isAvailable)
        XCTAssertEqual(entity.displayState, "unavailable")
    }

    func testUnknownAttributesDoNotFailDecoding() throws {
        let json = """
        {"entity_id":"sensor.x","state":"42","attributes":{"friendly_name":"X","battery":80,"some_complex":{"nested":[1,2]}}}
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.friendlyName, "X")
        XCTAssertEqual(entity.state, "42")
    }

    func testMissingFriendlyNameFallsBackToEntityID() throws {
        let json = """
        {"entity_id":"light.kitchen","state":"off","attributes":{}}
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.friendlyName, "light.kitchen")
        XCTAssertEqual(entity.domain, "light")
    }
}