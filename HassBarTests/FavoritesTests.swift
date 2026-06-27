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
}