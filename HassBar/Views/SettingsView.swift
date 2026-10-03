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
        .frame(minWidth: 680, minHeight: 480)
    }
}

// MARK: - Connection

struct ConnectionSettingsView: View {
    let store: HomeAssistantStore

    @State private var url = ""
    @State private var token = ""
    @State private var showToken = false
    @State private var status = TestStatus.idle
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()

    enum TestStatus: Equatable {
        case idle, testing, success, saved
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $url, prompt: Text("http://homeassistant.local:8123"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit { save() }

                LabeledContent("Access Token") { tokenField }
            } header: {
                Text("Home Assistant")
            } footer: {
                Text("Use an HTTP or HTTPS server URL and a long-lived access token. The token is stored in Keychain when you save.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    Button("Test Connection") { beginTest() }
                        .disabled(status == .testing || draftConnection == nil)
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftConnection == nil || !hasChanges)
                        .keyboardShortcut("s", modifiers: .command)
                    Spacer()
                }
                statusView
            }
        }
        .formStyle(.grouped)
        .controlSize(.regular)
        .onAppear { load() }
        .onChange(of: url) { invalidateTest() }
        .onChange(of: token) { invalidateTest() }
        .onDisappear {
            invalidateTest()
            showToken = false
        }
    }

    private var draftConnection: HAConnection? {
        guard let baseURL = try? HABaseURL.parse(url) else { return nil }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return nil }
        return HAConnection(baseURL: baseURL, token: trimmedToken)
    }

    private var hasChanges: Bool {
        draftConnection != store.config.connection
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if showToken { TextField("Access Token", text: $token) }
                else { SecureField("Access Token", text: $token) }
            }
            .labelsHidden()
            .textContentType(.password)
            .autocorrectionDisabled()
            .onSubmit { save() }

            Button { showToken.toggle() } label: {
                Image(systemName: showToken ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(showToken ? "Hide token" : "Show token")
            .help(showToken ? "Hide token" : "Show token")
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            if !url.isEmpty, (try? HABaseURL.parse(url)) == nil {
                Label("Enter an HTTP or HTTPS URL without a query, fragment, or embedded credentials.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if hasChanges {
                Text("Unsaved changes").foregroundStyle(.secondary)
            }
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing connection…").foregroundStyle(.secondary)
            }
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .saved:
            Label("Connection saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        url = store.config.haURL
        token = store.config.token ?? ""
    }

    private func invalidateTest() {
        testID = UUID()
        testTask?.cancel()
        testTask = nil
        status = .idle
    }

    private func save() {
        guard hasChanges else { return }
        invalidateTest()
        do {
            try store.config.saveConnection(url: url, token: token)
            store.reloadConfiguration()
            status = .saved
            Task { await store.refresh() }
        } catch let error as HAError {
            status = .failure(errorMessage(error))
        } catch {
            status = .failure("Could not save token to Keychain. Your saved connection was kept.")
        }
    }

    private func beginTest() {
        guard let connection = draftConnection else { return }
        invalidateTest()
        status = .testing
        let requestID = testID
        testTask = Task {
            do {
                try await store.testConnection(connection)
                guard !Task.isCancelled, requestID == testID else { return }
                status = .success
            } catch {
                guard !Task.isCancelled, requestID == testID else { return }
                status = .failure((error as? HAError).map(errorMessage) ?? error.localizedDescription)
            }
        }
    }

    private func errorMessage(_ error: HAError) -> String {
        switch error {
        case .invalidURL: return "Invalid server URL."
        case .missingToken: return "Missing token."
        case .invalidResponse: return "Invalid response from server."
        case .httpStatus(let code):
            switch code {
            case 401, 403: return "Authentication failed (\(code)). Check the token."
            case 404: return "Endpoint not found (404). Check the URL."
            default: return "HTTP \(code)."
            }
        case .transport: return "Could not reach server."
        case .decoding: return "Unexpected response from server."
        }
    }
}
