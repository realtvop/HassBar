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
        VStack(spacing: 0) {
            filterBar
            Divider()
            listContent
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search", text: $searchText, prompt: Text("Search by name or ID"))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Domain", selection: $selectedDomain) {
                Text("All Domains").tag(HADomain?.none)
                ForEach(HADomain.allCases, id: \.self) { domain in
                    Text(domain.rawValue).tag(HADomain?.some(domain))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()
        }
        .padding()
    }

    private var listContent: some View {
        List {
            if !store.favoriteRows.isEmpty {
                Section("Favorites") {
                    ForEach(store.favoriteRows) { entity in
                        EntityRow(
                            entity: entity,
                            alias: aliasBinding(for: entity.id),
                            isFavorite: true
                        ) {
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
                            alias: aliasBinding(for: entity.id),
                            isFavorite: store.favorites.contains(entity.id)
                        ) {
                            store.toggleFavorite(entity.id)
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }

    private var filteredEntities: [HAEntity] {
        store.allEntitiesSorted.filter { entity in
            if let domain = selectedDomain, entity.domain != domain.rawValue {
                return false
            }
            if !searchText.isEmpty {
                let needle = searchText.lowercased()
                if !entity.entityID.lowercased().contains(needle),
                   !entity.friendlyName.lowercased().contains(needle),
                   !store.displayName(for: entity).lowercased().contains(needle) {
                    return false
                }
            }
            return true
        }
    }

    private func aliasBinding(for entityID: String) -> Binding<String> {
        Binding(
            get: { store.alias(for: entityID) },
            set: { store.setAlias($0, for: entityID) }
        )
    }
}

// MARK: - Entity row

private struct EntityRow: View {
    let entity: HAEntity
    @Binding var alias: String
    let isFavorite: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                favoriteMark

                EntityIconBadge(entity: entity, size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.friendlyName)
                        .font(.system(size: 14, weight: .medium))
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
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            TextField("Alias", text: $alias, prompt: Text("Alias"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
        }
        .padding(.vertical, 6)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 6)
                    .fill(EntityMenuStyle.hoverBackground)
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var favoriteMark: some View {
        if isFavorite {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 18)
                .help("Favorite")
        } else {
            Color.clear
                .frame(width: 18)
        }
    }
}
