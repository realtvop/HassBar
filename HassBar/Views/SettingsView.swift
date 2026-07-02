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
    case menuBar
}

struct SettingsView: View {
    let store: HomeAssistantStore
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionSettingsView(store: store)
                .tabItem { Label("Connection", systemImage: "network") }
                .tag(SettingsTab.connection)

            EntitySelectionView(store: store)
                .tabItem { Label("Entities", systemImage: "star") }
                .tag(SettingsTab.entities)

            MenuBarSensorSettingsView(store: store)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)
        }
        .frame(minWidth: 600, minHeight: 460)
    }
}

// MARK: - Connection

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
            Section {
                TextField("Server URL", text: $url, prompt: Text("http://homeassistant.local:8123"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit { save() }

                LabeledContent("Access Token") {
                    tokenField
                }
            } header: {
                Text("Home Assistant")
            } footer: {
                Text("Enter the URL of your Home Assistant server and a long-lived access token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    statusView
                    Spacer()
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(status == .testing || url.isEmpty || token.isEmpty)
                }
            }
        }
        .formStyle(.columns)
        .controlSize(.regular)
        .padding()
        .onAppear { load() }
        .onDisappear { save() }
    }

    // MARK: - Token field

    private var tokenField: some View {
        HStack(spacing: 4) {
            Group {
                if showToken {
                    TextField("", text: $token)
                } else {
                    SecureField("", text: $token)
                }
            }
            .textContentType(.password)
            .autocorrectionDisabled()
            .onSubmit { save() }

            Button {
                showToken.toggle()
            } label: {
                Image(systemName: showToken ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(showToken ? "Hide token" : "Show token")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing connection…")
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
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
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedURL != store.config.haURL || trimmedToken != (store.config.token ?? "") else {
            return
        }

        store.config.haURL = trimmedURL
        do {
            try store.config.saveToken(trimmedToken)
        } catch {
            status = .failure("Could not save token to Keychain.")
            return
        }
        store.reloadConfiguration()
        status = .idle
    }

    private func testConnection() async {
        save()

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
