//
//  HomeAssistantClient.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

enum HAError: Error, Equatable {
    case missingToken
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case decoding
}

/// Connection coordinates required to talk to a Home Assistant instance.
struct HAConnection: Equatable, Sendable {
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

/// Home Assistant REST client. Owns no SwiftUI/App state.
///
/// Focused methods cover connection testing, state fetching, and service calls.
/// WebSocket subscribe/unsubscribe is added in a later step.
struct HomeAssistantClient: Sendable {
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

    /// Calls `POST /api/services/{domain}/{service}` with `{"entity_id": ...}`.
    func callService(domain: String, service: String, entityID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": entityID])
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