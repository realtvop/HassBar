//
//  HomeAssistantWebSocket.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

/// Realtime connection states surfaced to the store/UI.
enum HARealtimeStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case subscribing
    case connected
    case failed(String)
}

/// Decoded Home Assistant WebSocket event types we care about.
enum HAWebsocketEvent: Equatable, Sendable {
    case stateChanged(entityID: String, entity: HAEntity)
    case unknown
}

/// Errors emitted by the WebSocket client.
enum HAWebsocketError: Error, Equatable {
    case authRequired
    case authInvalid
    case authFailed(String)
    case unexpectedMessage
    case decodeError
}

/// Delegate-style sink for realtime events and connection state changes.
protocol HAWebsocketDelegate: AnyObject, Sendable {
    func realtime(didChange status: HARealtimeStatus)
    func realtime(didReceive event: HAWebsocketEvent)
}

/// Owns the Home Assistant WebSocket connection: handshake, auth, `subscribe_events`,
/// `state_changed` decoding, and bounded exponential-backoff reconnect.
///
/// The class is `Sendable`-annotated because it only mutates through async tasks
/// serialized on `URLSession`'s delegate queue + an internal `actor`. Swift 6
/// strict concurrency treats mutable properties as isolated behind the actor.
actor HomeAssistantWebSocket {
    private let baseURL: URL
    private let token: String
    private weak var delegate: (any HAWebsocketDelegate)?

    private var task: URLSessionWebSocketTask?
    private var nextID: Int = 1
    private var subscriptions: Set<String> = []
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var stopped = false

    private nonisolated let session: URLSession

    init(baseURL: URL, token: String, delegate: any HAWebsocketDelegate, session: URLSession = .shared) {
        self.session = session
        self.baseURL = baseURL
        self.token = token
        self.delegate = delegate
    }

    nonisolated var websocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        if components.scheme == "https" { components.scheme = "wss" }
        else if components.scheme == "http" { components.scheme = "ws" }
        components.path = "/api/websocket"
        return components.url ?? baseURL
    }

    func start() {
        guard !stopped else { return }
        receiveTask?.cancel()
        task?.cancel()
        task = nil
        subscriptions.removeAll()

        Task { @MainActor in
            await delegate?.realtime(didChange: .connecting)
        }
        let request = URLRequest(url: websocketURL)
        let newTask = session.webSocketTask(with: request)
        task = newTask
        newTask.resume()
        receiveTask?.cancel()
        let d = delegate
        let taskRef = newTask
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(task: taskRef, delegate: d)
        }
    }

    func stop() {
        stopped = true
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        subscriptions.removeAll()
        Task { @MainActor in
            await delegate?.realtime(didChange: .disconnected)
        }
    }

    // MARK: - Receive loop

    private func runReceiveLoop(task: URLSessionWebSocketTask, delegate: (any HAWebsocketDelegate)?) async {
        var authenticated = false
        while !stopped {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                if !stopped { await scheduleReconnect() }
                return
            }

            let data: Data
            switch message {
            case .data(let d): data = d
            case .string(let s): data = Data(s.utf8)
            @unknown default: continue
            }

            await handleMessage(data, task: task, authenticated: &authenticated, delegate: delegate)
        }
    }

    private func handleMessage(_ data: Data, task: URLSessionWebSocketTask, authenticated: inout Bool, delegate: (any HAWebsocketDelegate)?) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let type = json["type"] as? String {
            switch type {
            case "auth_required":
                await sendAuth(task: task)
                Task { @MainActor in await delegate?.realtime(didChange: .authenticating) }
                return
            case "auth_ok":
                authenticated = true
                Task { @MainActor in await delegate?.realtime(didChange: .subscribing) }
                await subscribeToStateChanges()
                Task { @MainActor in await delegate?.realtime(didChange: .connected) }
                reconnectAttempt = 0
                return
            case "auth_invalid":
                Task { @MainActor in await delegate?.realtime(didChange: .failed("Authentication failed")) }
                return
            default:
                break
            }
        }

        if authenticated, let eventType = json["type"] as? String, eventType == "event" {
            let event = json["event"] as? [String: Any]
            let eventData = event?["data"] as? [String: Any]
            if let eventType = eventData?["event_type"] as? String, eventType == "state_changed",
               let new = eventData?["new_state"] as? [String: Any],
               let entityID = new["entity_id"] as? String,
               let payload = try? JSONSerialization.data(withJSONObject: new),
               let entity = try? JSONDecoder().decode(HAEntity.self, from: payload) {
                Task { @MainActor in
                    await delegate?.realtime(didReceive: .stateChanged(entityID: entityID, entity: entity))
                }
            }
        }
    }

    // MARK: - Senders

    private func sendAuth(task: URLSessionWebSocketTask) async {
        let payload: [String: Any] = ["type": "auth", "access_token": token]
        await sendJSON(payload, task: task)
    }

    private func subscribeToStateChanges() async {
        guard let task else { return }
        let id = nextID
        nextID += 1
        let payload: [String: Any] = [
            "id": id,
            "type": "subscribe_events",
            "event_type": "state_changed",
        ]
        await sendJSON(payload, task: task)
        subscriptions.insert("state_changed")
    }

    private func sendJSON(_ payload: [String: Any], task: URLSessionWebSocketTask) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        try? await task.send(.data(data))
    }

    // MARK: - Reconnect

    private func scheduleReconnect() async {
        guard !stopped else { return }
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        if attempt > 8 {
            Task { @MainActor in
                await delegate?.realtime(didChange: .failed("Reconnect limit reached"))
            }
            return
        }
        let delay = min(pow(2.0, Double(attempt - 1)), 30.0)
        let nanos = UInt64(delay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
        guard !stopped else { return }
        start()
    }
}