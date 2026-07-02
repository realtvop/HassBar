//
//  MenuBarSensorSettingsView.swift
//  HassBar
//
//  Created by Codex on 2026/7/2.
//

import SwiftUI
import UniformTypeIdentifiers

struct MenuBarSensorSettingsView: View {
    let store: HomeAssistantStore

    @State private var searchText = ""
    @State private var draggedSensorID: String?

    var body: some View {
        Group {
            if !store.config.isConfigured {
                unconfiguredState
            } else {
                content
            }
        }
        .frame(minWidth: 640, minHeight: 450)
        .task {
            await store.refreshIfConfigured()
        }
    }

    private var unconfiguredState: some View {
        ContentUnavailableView {
            Label("Not Configured", systemImage: "network.slash")
        } description: {
            Text("Set up your Home Assistant connection to choose menu bar sensors.")
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()
            filterBar
            Divider()
            listContent
        }
    }

    private var optionsBar: some View {
        HStack {
            Toggle("Show app icon", isOn: showsAppIconInMenuBarBinding)
                .toggleStyle(.checkbox)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search", text: $searchText, prompt: Text("Search sensors"))
                .textFieldStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding()
    }

    private var listContent: some View {
        List {
            Section("Shown in Menu Bar") {
                if store.menuBarSensorRows.isEmpty {
                    Text("No menu bar sensors selected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.menuBarSensorRows) { row in
                        MenuBarSensorConfiguredRow(
                            row: row,
                            iconName: iconNameBinding(for: row.id),
                            showsIcon: showsIconBinding(for: row.id),
                            remove: {
                                store.removeMenuBarSensor(row.id)
                            },
                            dragHandle: MenuBarSensorDragHandle(
                                itemProvider: {
                                    draggedSensorID = row.id
                                    return NSItemProvider(object: row.id as NSString)
                                },
                                preview: AnyView(MenuBarSensorDragPreview(row: row))
                            )
                        )
                        .onDrop(
                            of: [.plainText],
                            delegate: MenuBarSensorDropDelegate(
                                targetID: row.id,
                                entityIDs: store.menuBarSensorRows.map(\.id),
                                draggedID: $draggedSensorID,
                                move: { ids, source, destination in
                                    store.moveMenuBarSensorsSubset(ids, from: source, to: destination)
                                }
                            )
                        )
                    }
                }
            }

            Section("Available Sensors (\(filteredSensors.count))") {
                if filteredSensors.isEmpty {
                    Text("No sensors match.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredSensors) { entity in
                        MenuBarSensorAvailableRow(
                            entity: entity,
                            isSelected: store.menuBarSensors.contains(entity.id),
                            add: {
                                store.addMenuBarSensor(entity.id)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }

    private var filteredSensors: [HAEntity] {
        store.sensorEntitiesSorted.filter { entity in
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return entity.entityID.lowercased().contains(needle)
                || entity.friendlyName.lowercased().contains(needle)
                || store.displayName(for: entity).lowercased().contains(needle)
        }
    }

    private func iconNameBinding(for entityID: String) -> Binding<String> {
        Binding(
            get: { store.menuBarSensorItem(for: entityID)?.iconName ?? "" },
            set: { store.setMenuBarSensorIconName($0, for: entityID) }
        )
    }

    private func showsIconBinding(for entityID: String) -> Binding<Bool> {
        Binding(
            get: { store.menuBarSensorItem(for: entityID)?.showsIcon ?? true },
            set: { store.setMenuBarSensorShowsIcon($0, for: entityID) }
        )
    }

    private var showsAppIconInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { store.showsAppIconInMenuBar },
            set: { store.setShowsAppIconInMenuBar($0) }
        )
    }
}

private struct MenuBarSensorConfiguredRow: View {
    let row: MenuBarSensorRow
    @Binding var iconName: String
    @Binding var showsIcon: Bool
    let remove: () -> Void
    let dragHandle: MenuBarSensorDragHandle

    @State private var isHovering = false
    @State private var showIconPicker = false

    var body: some View {
        HStack(spacing: 12) {
            EntityIconBadge(entity: row.entity, customIconName: resolvedPreviewIcon, size: 34)
                .opacity(showsIcon ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.entity.friendlyName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.entity.entityID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.entity.displayState)
                        .font(.caption)
                        .foregroundStyle(row.entity.isAvailable ? Color.secondary : Color.red)
                }
            }

            Spacer()

            Toggle("Icon", isOn: $showsIcon)
                .toggleStyle(.checkbox)
                .frame(width: 62, alignment: .leading)

            HStack(spacing: 4) {
                TextField("Icon", text: $iconName, prompt: Text("SF Symbol"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .disabled(!showsIcon)

                Button {
                    showIconPicker = true
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color(nsColor: .separatorColor).opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!showsIcon)
                .help("Browse icons")
                .popover(isPresented: $showIconPicker) {
                    IconPickerPopover(selection: $iconName, isPresented: $showIconPicker)
                }
            }
            .frame(width: 128)

            Button {
                remove()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from menu bar")

            dragHandle
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

    private var resolvedPreviewIcon: String? {
        showsIcon ? iconName : "eye.slash"
    }
}

private struct MenuBarSensorAvailableRow: View {
    let entity: HAEntity
    let isSelected: Bool
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            EntityIconBadge(entity: entity, size: 34)

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
                    Text(entity.displayState)
                        .font(.caption)
                        .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
                }
            }

            Spacer()

            Button {
                add()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isSelected)
            .help(isSelected ? "Already shown in menu bar" : "Show in menu bar")
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
}

private struct MenuBarSensorDragHandle: View {
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

private struct MenuBarSensorDragPreview: View {
    let row: MenuBarSensorRow

    var body: some View {
        HStack(spacing: 12) {
            EntityIconBadge(entity: row.entity, customIconName: row.item.iconName, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.entity.friendlyName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(row.entity.displayState)
                    .font(.caption)
                    .foregroundStyle(row.entity.isAvailable ? Color.secondary : Color.red)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MenuBarSensorDropDelegate: DropDelegate {
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
