//
//  SettingsView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

enum SettingsTab: Hashable {
    case connection
    case entities
}

struct SettingsView: View {
    let store: HomeAssistantStore
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionSettingsView(store: store)
                .tabItem { Label("Connection", systemImage: "link") }
                .tag(SettingsTab.connection)

            EntitySelectionView(store: store)
                .tabItem { Label("Entities", systemImage: "star") }
                .tag(SettingsTab.entities)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct ConnectionSettingsView: View {
    let store: HomeAssistantStore

    @State private var url: String = ""
    @State private var token: String = ""
    @State private var showToken: Bool = false
    @State private var status: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Home Assistant") {
                TextField("Server URL", text: $url, prompt: Text("http://homeassistant.local:8123"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                HStack {
                    if showToken {
                        TextField("Long-Lived Access Token", text: $token)
                    } else {
                        SecureField("Long-Lived Access Token", text: $token)
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showToken ? "Hide token" : "Show token")
                }
                .autocorrectionDisabled()
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(status == .testing || url.isEmpty || token.isEmpty)

                    Spacer()

                    Button("Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.isEmpty || token.isEmpty)
                }

                statusRow
            }
        }
        .formStyle(.grouped)
        .onAppear { load() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            HStack { ProgressView().controlSize(.small); Text("Testing…") }
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func load() {
        url = store.config.haURL
        token = store.config.token ?? ""
    }

    private func save() {
        store.config.haURL = url
        do {
            try store.config.saveToken(token)
        } catch {
            status = .failure("Could not save token to Keychain.")
            return
        }
        store.reloadConfiguration()
        status = .idle
    }

    private func testConnection() async {
        guard let urlValue = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = .failure("Invalid URL.")
            return
        }
        status = .testing
        let client = HomeAssistantClient(connection: HAConnection(baseURL: urlValue, token: token))
        do {
            try await client.testConnection()
            status = .success
        } catch let error as HAError {
            status = .failure(errorMessage(error))
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func errorMessage(_ error: HAError) -> String {
        switch error {
        case .missingToken: return "Missing token."
        case .invalidResponse: return "Invalid response from server."
        case .httpStatus(let code):
            switch code {
            case 401: return "Authentication failed (401). Check the token."
            case 404: return "Endpoint not found (404). Check the URL."
            default: return "HTTP \(code)."
            }
        case .transport: return "Could not reach server."
        case .decoding: return "Unexpected response from server."
        }
    }
}