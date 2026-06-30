//
//  EntitySelectionView.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import SwiftUI
import UniformTypeIdentifiers

struct EntitySelectionView: View {
    let store: HomeAssistantStore

    @State private var searchText: String = ""
    @State private var selectedDomain: HADomain? = nil
    @State private var draggedFavoriteID: String? = nil

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
            favoriteSections

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

    @ViewBuilder
    private var favoriteSections: some View {
        if !favoriteSensorRows.isEmpty {
            favoriteSection(
                title: "Favorite Sensors",
                entities: favoriteSensorRows
            )
        }

        if !favoriteDeviceRows.isEmpty {
            favoriteSection(
                title: "Favorite Devices",
                entities: favoriteDeviceRows
            )
        }
    }

    private func favoriteSection(title: String, entities: [HAEntity]) -> some View {
        Section(title) {
            ForEach(entities) { entity in
                EntityRow(
                    entity: entity,
                    alias: aliasBinding(for: entity.id),
                    isFavorite: true,
                    dragHandle: FavoriteDragHandle(
                        itemProvider: {
                            draggedFavoriteID = entity.id
                            return NSItemProvider(object: entity.id as NSString)
                        },
                        preview: AnyView(FavoriteDragPreview(entity: entity, alias: store.alias(for: entity.id)))
                    )
                ) {
                    store.toggleFavorite(entity.id)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: FavoriteDropDelegate(
                        targetID: entity.id,
                        entityIDs: entities.map(\.id),
                        draggedID: $draggedFavoriteID,
                        move: { ids, source, destination in
                            store.moveFavoriteSubset(ids, from: source, to: destination)
                        }
                    )
                )
            }
        }
    }

    private var favoriteSensorRows: [HAEntity] {
        store.favoriteRows.filter(Self.isSensor)
    }

    private var favoriteDeviceRows: [HAEntity] {
        store.favoriteRows.filter { !Self.isSensor($0) }
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

    nonisolated private static func isSensor(_ entity: HAEntity) -> Bool {
        entity.entityID.hasPrefix("sensor.") || entity.entityID.hasPrefix("binary_sensor.")
    }
}

// MARK: - Entity row

private struct EntityRow: View {
    let entity: HAEntity
    @Binding var alias: String
    let isFavorite: Bool
    var dragHandle: FavoriteDragHandle? = nil
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

            if let dragHandle {
                dragHandle
            }
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

private struct FavoriteDragHandle: View {
    let itemProvider: () -> NSItemProvider
    let preview: AnyView

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onDrag(itemProvider) {
                preview
            }
            .help("Drag to Reorder")
    }
}

private struct FavoriteDragPreview: View {
    let entity: HAEntity
    let alias: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 18)

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

            Text(alias.isEmpty ? "Alias" : alias)
                .font(.system(size: 13))
                .foregroundStyle(alias.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 520, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FavoriteDropDelegate: DropDelegate {
    let targetID: String
    let entityIDs: [String]
    @Binding var draggedID: String?
    let move: ([String], IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedID,
            draggedID != targetID,
            let sourceIndex = entityIDs.firstIndex(of: draggedID),
            let targetIndex = entityIDs.firstIndex(of: targetID)
        else { return }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        move(entityIDs, IndexSet(integer: sourceIndex), destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}
