import SwiftUI

/// Shared feedback for both entity-management tabs, including a manual refresh path.
struct EntityCacheStatusView: View {
    let store: HomeAssistantStore

    var body: some View {
        HStack(spacing: 8) {
            if store.isLoading {
                ProgressView().controlSize(.small)
                Text("Loading entities…")
            } else if let error = store.lastError {
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if let updated = store.lastUpdated {
                Text("\(store.entities.count) entities · Updated \(updated.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Entities have not been loaded.")
            }
            Spacer(minLength: 8)
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

struct MissingEntityRow: View {
    let entityID: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(entityID).lineLimit(1).help(entityID)
                Text("No longer returned by this server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", action: remove)
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(entityID)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remove \(entityID). No longer returned by this server.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { remove() }
        .accessibilityAction(named: Text("Remove selection")) { remove() }
    }
}
