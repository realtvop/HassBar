import XCTest
@testable import HassBar

final class ControlRobustnessTests: XCTestCase {
    private func decode(_ attributes: String, id: String = "light.test", state: String = "on") throws -> HAEntity {
        try JSONDecoder().decode(HAEntity.self, from: Data("{\"entity_id\":\"\(id)\",\"state\":\"\(state)\",\"attributes\":\(attributes)}".utf8))
    }

    func testMalformedOptionalAttributesAndExtremeNumbersDoNotCrash() throws {
        let entity = try decode(#"{"friendly_name":{},"unit_of_measurement":5,"brightness":"1e100","color_temp_kelvin":"NaN","current_temperature":"Infinity"}"#)
        XCTAssertEqual(entity.friendlyName, "light.test")
        XCTAssertNil(entity.attributes.brightness)
        XCTAssertNil(entity.attributes.colorTempKelvin)
        XCTAssertNil(entity.attributes.currentTemperature)
    }

    func testInvalidColorTemperatureRangesAreIgnored() throws {
        for attributes in [#"{"min_color_temp_kelvin":6500,"max_color_temp_kelvin":2000}"#, #"{"min_color_temp_kelvin":0,"max_color_temp_kelvin":6500}"#, #"{"min_color_temp_kelvin":2000,"max_color_temp_kelvin":2000}"#] {
            XCTAssertNil(try decode(attributes).colorTempRange)
        }
    }

    func testLightCapabilitiesAreIndependentOfCurrentBrightness() throws {
        XCTAssertTrue(try decode(#"{"supported_color_modes":["rgb"]}"#, state: "off").supportsBrightness)
        XCTAssertFalse(try decode(#"{"supported_color_modes":["onoff"],"brightness":255}"#).supportsBrightness)
        XCTAssertEqual(try decode(#"{"brightness":999}"#).brightnessPercent, 100)
        XCTAssertEqual(try decode(#"{"brightness":-1}"#).brightnessPercent, 0)
    }

    func testUnknownSceneStateStillAllowsRun() throws {
        XCTAssertTrue(try decode("{}", id: "scene.movie", state: "unknown").isAvailable)
        XCTAssertFalse(try decode("{}", id: "scene.movie", state: "unavailable").isAvailable)
        XCTAssertFalse(try decode("{}", state: "unknown").isAvailable)
    }

    func testCoverAndClimateRespectAdvertisedCapabilities() throws {
        let cover = try decode(#"{"supported_features":3}"#, id: "cover.blinds", state: "opening")
        XCTAssertEqual(EntityActionMapping.displayActions(for: cover).map(\.service), ["close_cover"])
        let climate = try decode(#"{"supported_features":2,"min_temp":16,"max_temp":30}"#, id: "climate.ac")
        XCTAssertFalse(climate.supportsClimateTargetTemperature)
        XCTAssertTrue(EntityActionMapping.displayActions(for: climate).isEmpty)
    }

    func testSliderRoundingUsesLowerBoundAndStaysInRange() {
        let range = 16.25...30.25
        XCTAssertEqual(SliderValueScale.quantized(17.24, range: range, step: 0.5), 17.25)
        XCTAssertEqual(SliderValueScale.quantized(100, range: range, step: 0.5), 30.25)
        XCTAssertEqual(SliderValueScale.quantized(.nan, range: range, step: 0), 16.25)
    }

    func testPersistedFavoritesNormalizeDuplicateAndEmptyIDs() throws {
        let favorites = try XCTUnwrap(Favorites(rawValue: #"["light.a","","light.a","sensor.b"]"#))
        XCTAssertEqual(favorites.entityIDs, ["light.a", "sensor.b"])
    }
}
