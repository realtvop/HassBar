//
//  HomeAssistantClient.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

nonisolated enum HAError: Error, Equatable {
    case missingToken
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case decoding
}

nonisolated extension HAError {
    var userMessage: String {
        switch self {
        case .missingToken: return "Add an access token in Connection settings."
        case .invalidURL: return "Check the server URL in Connection settings."
        case .httpStatus(401), .httpStatus(403): return "Authentication failed. Check the access token."
        case .httpStatus(404): return "Endpoint not found. Check the server URL."
        case .httpStatus(let code): return "Server returned HTTP \(code)."
        case .transport: return "Could not reach Home Assistant."
        case .invalidResponse: return "Invalid response from Home Assistant."
        case .decoding: return "Could not read the entity states."
        }
    }
}

/// Accepts an HTTP(S) server root or reverse-proxy prefix, without credentials or query data.
nonisolated enum HABaseURL {
    static func parse(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw HAError.invalidURL
        }
        components.scheme = scheme
        guard let url = components.url else { throw HAError.invalidURL }
        return url
    }
}

/// Connection coordinates required to talk to a Home Assistant instance.
nonisolated struct HAConnection: Equatable, Sendable {
    let baseURL: URL
    let token: String
}

/// Pure construction of Home Assistant REST requests.
///
/// Kept separate from the transport so request shape (URL, headers, body) can be
/// unit-tested without a live server.
enum HARequestBuilder {
    static func makeRequest(
        baseURL: URL,
        token: String,
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard !token.isEmpty else { throw HAError.missingToken }
        _ = try HABaseURL.parse(baseURL.absoluteString)
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(trimmedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = body
        }
        return request
    }
}

/// Home Assistant REST transport protocol, isolated so tests can inject a fake.
protocol HomeAssistantCalling: Sendable {
    func testConnection() async throws
    func fetchStates() async throws -> [HAEntity]
    func fetchEntity(entityID: String) async throws -> HAEntity
    func callService(domain: String, service: String, entityID: String, serviceData: [String: Any]?) async throws
}

extension HomeAssistantCalling {
    /// Convenience overload for service calls that do not need extra data.
    func callService(domain: String, service: String, entityID: String) async throws {
        try await callService(domain: domain, service: service, entityID: entityID, serviceData: nil)
    }
}

/// Home Assistant REST client. Owns no SwiftUI/App state.
///
/// Focused methods cover connection testing, state fetching, and service calls.
/// Realtime transport lives in `HomeAssistantWebSocket`.
struct HomeAssistantClient: HomeAssistantCalling, Sendable {
    let connection: HAConnection
    let session: URLSession
    private let decoder = JSONDecoder()

    init(connection: HAConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    /// Verifies the configured URL and token by hitting `GET /api/`.
    /// Succeeds on any 2xx response.
    func testConnection() async throws {
        let request = try HARequestBuilder.makeRequest(
            baseURL: connection.baseURL,
            token: connection.token,
            path: "api/"
        )
        let (_, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw HAError.httpStatus(http.statusCode)
        }
    }

    /// Fetches all entity states via `GET /api/states`.
    func fetchStates() async throws -> [HAEntity] {
        let request = try HARequestBuilder.makeRequest(
            baseURL: connection.baseURL,
            token: connection.token,
            path: "api/states"
        )
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw HAError.httpStatus(http.statusCode)
        }
        do {
            return try decoder.decode([HAEntity].self, from: data)
        } catch {
            throw HAError.decoding
        }
    }

    /// Fetches a single entity state via `GET /api/states/{entity_id}`.
    /// Used to refresh one entity's state immediately after a service call,
    /// without waiting for a WebSocket `state_changed` event.
    func fetchEntity(entityID: String) async throws -> HAEntity {
        let request = try HARequestBuilder.makeRequest(
            baseURL: connection.baseURL,
            token: connection.token,
            path: "api/states/\(entityID)"
        )
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw HAError.httpStatus(http.statusCode)
        }
        do {
            return try decoder.decode(HAEntity.self, from: data)
        } catch {
            throw HAError.decoding
        }
    }

    /// Calls `POST /api/services/{domain}/{service}` with `{"entity_id": ...}` plus any
    /// additional `serviceData` entries (e.g. `brightness`, `color_temp_kelvin`).
    func callService(domain: String, service: String, entityID: String, serviceData: [String: Any]? = nil) async throws {
        var payload: [String: Any] = ["entity_id": entityID]
        if let serviceData {
            for (key, value) in serviceData {
                payload[key] = value
            }
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try HARequestBuilder.makeRequest(
            baseURL: connection.baseURL,
            token: connection.token,
            path: "api/services/\(domain)/\(service)",
            method: "POST",
            body: body
        )
        let (_, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw HAError.httpStatus(http.statusCode)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HAError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HAError.invalidResponse
        }
        return (data, http)
    }
}
