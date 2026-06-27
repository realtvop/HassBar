import XCTest
@testable import HassBar

final class HARequestBuilderTests: XCTestCase {
    private let url = URL(string: "http://ha.local:8123")!
    private let token = "ABC123"

    func testBuilder_assemblesGETStatesRequest() throws {
        let request = try HARequestBuilder.makeRequest(baseURL: url, token: token, path: "api/states")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://ha.local:8123/api/states")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ABC123")
        XCTAssertNil(request.httpBody)
    }

    func testBuilder_acceptsLeadingSlash() throws {
        let request = try HARequestBuilder.makeRequest(baseURL: url, token: token, path: "/api/")
        XCTAssertEqual(request.url?.absoluteString, "http://ha.local:8123/api/")
    }

    func testBuilder_serviceCallHasJSONBodyAndPost() throws {
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": "light.kitchen"])
        let request = try HARequestBuilder.makeRequest(
            baseURL: url, token: token, path: "api/services/light/turn_on", method: "POST", body: body
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let decoded = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(decoded?["entity_id"], "light.kitchen")
    }

    func testBuilder_throwsWhenTokenMissing() {
        XCTAssertThrowsError(try HARequestBuilder.makeRequest(baseURL: url, token: "", path: "api/states")) { error in
            XCTAssertEqual(error as? HAError, .missingToken)
        }
    }
}