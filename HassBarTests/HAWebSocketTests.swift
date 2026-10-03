import XCTest
@testable import HassBar

final class HAWebSocketTests: XCTestCase {
    private func decode(_ json: String) throws -> HAWebSocketMessage {
        try JSONDecoder().decode(HAWebSocketMessage.self, from: Data(json.utf8))
    }

    func testOfficialStateChangedEnvelope() throws {
        let message = try decode(#"{"id":1,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.desk","new_state":{"entity_id":"light.desk","state":"on","attributes":{"brightness":128}}}}}"#)
        guard case .stateChanged(let id, let entity) = message.stateChange else {
            return XCTFail("Official event envelope was not decoded")
        }
        XCTAssertEqual(id, "light.desk")
        XCTAssertEqual(entity.brightnessPercent, 50)
    }

    func testRemovedEntityEvent() throws {
        let message = try decode(#"{"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"sensor.old","new_state":null}}}"#)
        XCTAssertEqual(message.stateChange, .entityRemoved(entityID: "sensor.old"))
    }

    func testMismatchedEntityDoesNotChangeCache() throws {
        let message = try decode(#"{"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.a","new_state":{"entity_id":"light.b","state":"on","attributes":{}}}}}"#)
        XCTAssertNil(message.stateChange)
    }

    func testConnectionRequiresMatchingSubscriptionAcknowledgement() throws {
        var handshake = HAWebSocketHandshake(subscriptionID: 1)
        XCTAssertEqual(handshake.receive(try decode(#"{"type":"auth_required"}"#)), .authenticate)
        XCTAssertEqual(handshake.receive(try decode(#"{"type":"auth_ok"}"#)), .subscribe)
        XCTAssertFalse(handshake.isConnected)
        XCTAssertNil(handshake.receive(try decode(#"{"type":"result","id":2,"success":true}"#)))
        XCTAssertFalse(handshake.isConnected)
        XCTAssertEqual(handshake.receive(try decode(#"{"type":"result","id":1,"success":true}"#)), .connected)
        XCTAssertTrue(handshake.isConnected)
    }

    func testSubscriptionFailureAndInvalidAuthentication() throws {
        var handshake = HAWebSocketHandshake(subscriptionID: 1)
        _ = handshake.receive(try decode(#"{"type":"auth_required"}"#))
        _ = handshake.receive(try decode(#"{"type":"auth_ok"}"#))
        XCTAssertEqual(handshake.receive(try decode(#"{"type":"result","id":1,"success":false,"error":{"message":"Denied"}}"#)), .failed("Denied"))
        XCTAssertFalse(handshake.isConnected)
        XCTAssertEqual(handshake.receive(try decode(#"{"type":"auth_invalid"}"#)), .failed("Authentication failed. Check the access token."))
    }

    @MainActor
    func testWebSocketPreservesReverseProxyPrefix() async {
        let store = HomeAssistantStore(config: TestSupport.makeConfig(), startRealtimeOnRefresh: false)
        let ws = HomeAssistantWebSocket(baseURL: URL(string: "https://ha.example/prefix/")!, token: "T", delegate: store)
        XCTAssertEqual(ws.websocketURL.absoluteString, "wss://ha.example/prefix/api/websocket")
        await ws.stop()
    }
}
