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
        Group {
            if !store.config.isConfigured {
                unconfiguredState
            } else {
                entityList
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .task {
            await store.refreshIfConfigured()
        }
    }

    // MARK: - Unconfigured state

    private var unconfiguredState: some View {
        ContentUnavailableView {
            Label("Not Configured", systemImage: "network.slash")
        } description: {
            Text("Set up your Home Assistant connection to choose favorite entities.")
        }
    }

    // MARK: - Entity list

    private var entityList: some View {
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
        .listStyle(.inset)
        .searchable(text: $searchText, prompt: "Search by name or ID")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Domain", selection: $selectedDomain) {
                    Text("All Domains").tag(HADomain?.none)
                    ForEach(HADomain.allCases, id: \.self) { domain in
                        Text(domain.rawValue).tag(HADomain?.some(domain))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
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

// MARK: - Entity row

private struct EntityRow: View {
    let entity: HAEntity
    let isFavorite: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .frame(width: 20)
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
        .padding(.vertical, 1)
    }
}
