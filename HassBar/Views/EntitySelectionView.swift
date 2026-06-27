//
//  EntitySelectionView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI

struct EntitySelectionView: View {
    let store: HomeAssistantStore

    @State private var searchText: String = ""
    @State private var selectedDomain: HADomain? = nil

    var body: some View {
        List {
            if !store.favoriteRows.isEmpty {
                Section("Favorites") {
                    ForEach(store.favoriteRows) { entity in
                        EntityRow(entity: entity, isFavorite: true) {
                            store.toggleFavorite(entity.id)
                        }
                    }
                    .onMove { source, destination in
                        store.moveFavorites(from: source, to: destination)
                    }
                }
            }

            Section("All Entities (\(filteredEntities.count))") {
                if filteredEntities.isEmpty {
                    Text("No entities match.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredEntities) { entity in
                        EntityRow(
                            entity: entity,
                            isFavorite: store.favorites.contains(entity.id)
                        ) {
                            store.toggleFavorite(entity.id)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by name or id")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Domain", selection: $selectedDomain) {
                    Text("All Domains").tag(HADomain?.none)
                    ForEach(HADomain.allCases, id: \.self) { domain in
                        Text(domain.rawValue).tag(HADomain?.some(domain))
                    }
                }
                .frame(width: 160)
            }
        }
        .task {
            await store.refreshIfConfigured()
        }
    }

    private var filteredEntities: [HAEntity] {
        store.allEntitiesSorted.filter { entity in
            if let domain = selectedDomain, entity.domain != domain.rawValue {
                return false
            }
            if !searchText.isEmpty {
                let needle = searchText.lowercased()
                if !entity.entityID.lowercased().contains(needle),
                   !entity.friendlyName.lowercased().contains(needle) {
                    return false
                }
            }
            return true
        }
    }
}

private struct EntityRow: View {
    let entity: HAEntity
    let isFavorite: Bool
    let toggle: () -> Void

    var body: some View {
        HStack {
            Button(action: toggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 1) {
                Text(entity.friendlyName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entity.entityID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entity.state)
                        .font(.caption)
                        .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
                }
            }
            Spacer()
        }
    }
}