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

    func testDecodesLightAttributes() throws {
        let json = """
        {
            "entity_id": "light.bedroom",
            "state": "on",
            "attributes": {
                "friendly_name": "Bedroom",
                "brightness": 128,
                "color_temp_kelvin": 3500,
                "min_color_temp_kelvin": 2000,
                "max_color_temp_kelvin": 6500,
                "supported_color_modes": ["color_temp", "brightness"]
            }
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.brightnessPercent, 50)
        XCTAssertTrue(entity.supportsBrightness)
        XCTAssertTrue(entity.supportsColorTemperature)
        XCTAssertEqual(entity.colorTempRange, 2000...6500)
    }

    func testDecodesMiredColorTemperatureRange() throws {
        let json = """
        {
            "entity_id": "light.legacy_bulb",
            "state": "on",
            "attributes": {
                "color_temp": 370,
                "min_mireds": 153,
                "max_mireds": 500,
                "supported_color_modes": ["color_temp"]
            }
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertTrue(entity.supportsColorTemperature)
        XCTAssertEqual(entity.colorTempKelvin, 2703)
        XCTAssertEqual(entity.colorTempRange, 2000...6536)
    }

    func testDecodesLossyLightNumberAttributes() throws {
        let json = """
        {
            "entity_id": "light.tolerant_bulb",
            "state": "on",
            "attributes": {
                "brightness": 127.6,
                "color_temp_kelvin": "3499.6",
                "min_color_temp_kelvin": "2000",
                "max_color_temp_kelvin": 6500.4,
                "supported_color_modes": ["color_temp"]
            }
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertEqual(entity.attributes.brightness, 128)
        XCTAssertEqual(entity.colorTempKelvin, 3500)
        XCTAssertEqual(entity.colorTempRange, 2000...6500)
    }

    func testDecodesClimateAttributes() throws {
        let json = """
        {
            "entity_id": "climate.bedroom",
            "state": "cool",
            "attributes": {
                "friendly_name": "Bedroom AC",
                "current_temperature": "26.5",
                "temperature": 24,
                "min_temp": 16,
                "max_temp": 30,
                "target_temp_step": "0.5",
                "temperature_unit": "°C",
                "hvac_modes": ["off", "cool", "heat", "dry", "fan_only"]
            }
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)

        XCTAssertTrue(entity.isClimate)
        XCTAssertTrue(entity.isClimateActive)
        XCTAssertEqual(entity.climateCurrentTemperature, 26.5)
        XCTAssertEqual(entity.climateTargetTemperature, 24)
        XCTAssertEqual(entity.climateTemperatureRange, 16...30)
        XCTAssertEqual(entity.climateTemperatureStep, 0.5)
        XCTAssertEqual(entity.climateTemperatureUnit, "°C")
        XCTAssertEqual(entity.climateHVACModes, ["off", "cool", "heat", "dry", "fan_only"])
    }

    func testColorTemperatureRGBComponents() {
        let warm = ColorTemperatureRGB.components(forKelvin: 2000)
        let daylight = ColorTemperatureRGB.components(forKelvin: 6500)

        XCTAssertEqual(warm.red, 1, accuracy: 0.001)
        XCTAssertGreaterThan(warm.green, warm.blue)
        XCTAssertLessThan(warm.blue, 0.25)
        XCTAssertEqual(daylight.red, 1, accuracy: 0.001)
        XCTAssertGreaterThan(daylight.green, 0.95)
        XCTAssertGreaterThan(daylight.blue, 0.95)
    }

    func testLightWithoutColorTempModeDoesNotSupportTemperature() throws {
        let json = """
        {
            "entity_id": "light.rgb",
            "state": "on",
            "attributes": {
                "brightness": 255,
                "supported_color_modes": ["rgb"]
            }
        }
        """.data(using: .utf8)!
        let entity = try JSONDecoder().decode(HAEntity.self, from: json)
        XCTAssertTrue(entity.supportsBrightness)
        XCTAssertFalse(entity.supportsColorTemperature)
    }
}
