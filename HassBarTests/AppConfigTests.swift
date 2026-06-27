import XCTest
@testable import HassBar

final class AppConfigTests: XCTestCase {
    func testDefaultsUnconfigured() {
        let config = TestSupport.makeConfig()
        XCTAssertEqual(config.haURL, "")
        XCTAssertNil(config.token)
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.favorites.entityIDs, [])
    }

    func testRoundTripURLAndFavorites() {
        let config = TestSupport.makeConfig()
        config.haURL = "  http://ha.local:8123  "
        XCTAssertEqual(config.haURL, "http://ha.local:8123")
        config.favorites = Favorites(entityIDs: ["a", "b"])
        XCTAssertEqual(config.favorites.entityIDs, ["a", "b"])
    }

    func testTokenRoundTrip() throws {
        let config = TestSupport.makeConfig()
        try config.saveToken("TOKEN-XYZ")
        XCTAssertEqual(config.token, "TOKEN-XYZ")
        XCTAssertTrue(config.isConfigured == false) // no URL set yet
    }

    func testIsConfiguredRequiresValidURLAndToken() throws {
        let config = TestSupport.makeConfig()
        XCTAssertFalse(config.isConfigured)
        config.haURL = "http://ha.local:8123"
        try config.saveToken("T")
        XCTAssertTrue(config.isConfigured)
    }

    func testIsConfiguredRejectsURLsMissingHost() throws {
        let config = TestSupport.makeConfig()
        config.haURL = "not a url"
        try config.saveToken("T")
        XCTAssertFalse(config.isConfigured)
    }

    func testClearTokenRemovesIt() throws {
        let config = TestSupport.makeConfig()
        try config.saveToken("T")
        config.clearToken()
        XCTAssertNil(config.token)
    }
}