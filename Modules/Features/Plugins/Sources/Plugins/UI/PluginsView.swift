//
//  PluginsView.swift
//  Plugins
//
//  Browse, install, and manage plugins.
//

import SwiftUI

/// The plugin manager.
///
/// Installed plugins first, then the registry. Nothing here executes a plugin or knows what a
/// `MusicSource` is — installing writes source text to disk, and the composition root turns that
/// into a playable source on next launch.
public struct PluginsView: View {
    @Environment(PluginStore.self) private var store

    @State private var query = ""
    @State private var installing: Set<String> = []

    public init() {}

    public var body: some View {
        List {
            if !store.installed.isEmpty {
                Section("Installed") {
                    ForEach(store.installed) { plugin in
                        InstalledPluginRow(plugin: plugin, hasUpdate: store.hasUpdate(plugin))
                    }
                }
            }

            Section("Browse") {
                if store.isRefreshing, store.catalog.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading plugins…").foregroundStyle(.secondary)
                    }
                } else if let error = store.lastError, store.catalog.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load plugins",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else {
                    ForEach(filteredCatalog) { entry in
                        CatalogRow(
                            entry: entry,
                            isInstalled: store.installed.contains { $0.id == entry.id },
                            isInstalling: installing.contains(entry.id),
                            install: { await install(entry) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Plugins")
        .searchable(text: $query, prompt: "Search plugins")
        .refreshable { await store.refreshCatalog() }
        .task {
            guard store.catalog.isEmpty else { return }
            await store.refreshCatalog()
        }
    }

    private var filteredCatalog: [RegistryEntry] {
        // Only MODULE entries are music sources; the registry also lists ARTWORK and CONNECTOR
        // types that this screen has nothing to do with.
        let modules = store.catalog.filter { $0.type == "MODULE" }
        guard !query.isEmpty else { return modules }

        return modules.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func install(_ entry: RegistryEntry) async {
        installing.insert(entry.id)
        defer { installing.remove(entry.id) }
        try? await store.install(entry)
    }
}

private struct InstalledPluginRow: View {
    @Environment(PluginStore.self) private var store

    let plugin: InstalledPlugin
    let hasUpdate: Bool

    var body: some View {
        NavigationLink {
            PluginDetailView(pluginID: plugin.id)
        } label: {
            HStack(spacing: 12) {
                PluginIcon(url: plugin.iconURL)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                    HStack(spacing: 6) {
                        Text(plugin.version.isEmpty ? "unversioned" : plugin.version)
                        if hasUpdate {
                            Text("Update available")
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { newValue in
                        Task { await store.setEnabled(newValue, for: plugin.id) }
                    }
                ))
                .labelsHidden()
            }
        }
    }
}

private struct CatalogRow: View {
    let entry: RegistryEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let install: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            PluginIcon(url: entry.iconURL)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                    if entry.isTrusted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }

                if let author = entry.author {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                }

                if !entry.labels.isEmpty {
                    Text(entry.labels.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
            } else if isInstalling {
                ProgressView()
            } else {
                Button("Get") { Task { await install() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct PluginIcon: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
