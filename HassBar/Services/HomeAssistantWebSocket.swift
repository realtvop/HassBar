import Foundation

nonisolated enum HARealtimeStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case subscribing
    case connected
    case failed(String)
}

nonisolated enum HAWebsocketEvent: Equatable, Sendable {
    case stateChanged(entityID: String, entity: HAEntity)
    case entityRemoved(entityID: String)
    case unknown
}

@MainActor
protocol HAWebsocketDelegate: AnyObject, Sendable {
    func realtime(didChange status: HARealtimeStatus)
    func realtime(didReceive event: HAWebsocketEvent)
}

/// Wire format shared by the transport and protocol regression tests.
nonisolated struct HAWebSocketMessage: Decodable {
    let type: String
    var id: Int?
    var success: Bool?
    var message: String?
    var error: Failure?
    var event: Event?

    struct Failure: Decodable {
        var message: String?
    }

    struct Event: Decodable {
        let eventType: String
        let data: StateChange

        enum CodingKeys: String, CodingKey {
            case eventType = "event_type"
            case data
        }
    }

    struct StateChange: Decodable {
        let entityID: String
        let newState: HAEntity?

        enum CodingKeys: String, CodingKey {
            case entityID = "entity_id"
            case newState = "new_state"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entityID = try container.decode(String.self, forKey: .entityID)
            newState = try container.decode(HAEntity?.self, forKey: .newState)
        }
    }

    var stateChange: HAWebsocketEvent? {
        guard type == "event", let event, event.eventType == "state_changed" else { return nil }
        if let entity = event.data.newState {
            guard entity.entityID == event.data.entityID else { return nil }
            return .stateChanged(entityID: entity.entityID, entity: entity)
        }
        return .entityRemoved(entityID: event.data.entityID)
    }
}

/// Tracks authentication and the matching subscription acknowledgement.
nonisolated struct HAWebSocketHandshake {
    enum Action: Equatable {
        case authenticate
        case subscribe
        case connected
        case failed(String)
    }

    private enum Phase { case authentication, authenticating, subscribing, connected }
    private var phase = Phase.authentication
    let subscriptionID: Int

    init(subscriptionID: Int) {
        self.subscriptionID = subscriptionID
    }

    var isConnected: Bool { phase == .connected }

    mutating func receive(_ message: HAWebSocketMessage) -> Action? {
        switch (phase, message.type) {
        case (_, "auth_invalid"):
            return .failed("Authentication failed. Check the access token.")
        case (.authentication, "auth_required"):
            phase = .authenticating
            return .authenticate
        case (.authenticating, "auth_ok"):
            phase = .subscribing
            return .subscribe
        case (.subscribing, "result") where message.id == subscriptionID:
            guard message.success == true else {
                return .failed(message.error?.message ?? "Event subscription failed")
            }
            phase = .connected
            return .connected
        default:
            return nil
        }
    }
}

nonisolated protocol HARealtimeConnecting: Sendable {
    func start() async
    func stop() async
}

/// One receive/reconnect task per connection; cancellation invalidates all old work.
actor HomeAssistantWebSocket: HARealtimeConnecting {
    private let baseURL: URL
    private let token: String
    private weak var delegate: (any HAWebsocketDelegate)?
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var generation = UUID()

    init(baseURL: URL, token: String, delegate: any HAWebsocketDelegate, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.delegate = delegate
        self.session = session
    }

    nonisolated var websocketURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }

    func start() {
        guard receiveTask == nil else { return }
        let currentGeneration = generation
        receiveTask = Task { [weak self] in
            await self?.run(generation: currentGeneration)
        }
    }

    func stop() {
        generation = UUID()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        // The owner updates its UI immediately; a stopped connection emits no late callbacks.
    }

    private func isCurrent(_ expected: UUID) -> Bool {
        generation == expected && !Task.isCancelled
    }

    private func report(_ status: HARealtimeStatus, generation: UUID) async {
        guard isCurrent(generation) else { return }
        await delegate?.realtime(didChange: status)
    }

    private func run(generation: UUID) async {
        var attempts = 0
        while isCurrent(generation) {
            await report(.connecting, generation: generation)
            guard isCurrent(generation) else { return }
            let task = session.webSocketTask(with: websocketURL)
            socket = task
            task.resume()
            var handshake = HAWebSocketHandshake(subscriptionID: 1)
            do {
                while isCurrent(generation) {
                    let incoming = try await task.receive()
                    guard isCurrent(generation) else { return }
                    let data: Data
                    switch incoming {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    guard let message = try? JSONDecoder().decode(HAWebSocketMessage.self, from: data) else { continue }
                    if let action = handshake.receive(message) {
                        switch action {
                        case .authenticate:
                            await report(.authenticating, generation: generation)
                            guard isCurrent(generation) else { return }
                            try await send(["type": "auth", "access_token": token], on: task)
                        case .subscribe:
                            await report(.subscribing, generation: generation)
                            guard isCurrent(generation) else { return }
                            try await send(["id": 1, "type": "subscribe_events", "event_type": "state_changed"], on: task)
                        case .connected:
                            attempts = 0
                            await report(.connected, generation: generation)
                        case .failed(let message):
                            task.cancel(with: .policyViolation, reason: nil)
                            await report(.failed(message), generation: generation)
                            if isCurrent(generation) { receiveTask = nil; socket = nil }
                            return
                        }
                    }
                    if handshake.isConnected, let event = message.stateChange, isCurrent(generation) {
                        await delegate?.realtime(didReceive: event)
                    }
                }
            } catch {
                guard isCurrent(generation) else { return }
                task.cancel(with: .goingAway, reason: nil)
                socket = nil
                attempts += 1
                guard attempts <= 8 else {
                    await report(.failed("Reconnect limit reached. Refresh to retry."), generation: generation)
                    if isCurrent(generation) { receiveTask = nil }
                    return
                }
                await report(.connecting, generation: generation)
                do {
                    try await Task.sleep(for: .seconds(min(pow(2, Double(attempts - 1)), 30)))
                } catch { return }
            }
        }
    }

    private func send(_ payload: [String: Any], on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
