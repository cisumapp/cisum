//
//  PluginStore.swift
//  Plugins
//
//  Install, enable, configure, remove. The catalog's whole job.
//

import Foundation
import Observation
import Utilities

/// Owns the user's installed plugins.
///
/// `@Observable` and `@MainActor` because the plugin management UI binds to it directly. Disk and
/// network work hops off the main actor; only the published arrays stay here.
@Observable
@MainActor
public final class PluginStore {
    /// Everything the user has installed, newest first.
    public private(set) var installed: [InstalledPlugin] = []

    /// The registry listing, populated by `refreshCatalog()`.
    public private(set) var catalog: [RegistryEntry] = []

    /// Set when a catalog refresh or install fails, for display.
    public private(set) var lastError: String?

    public private(set) var isRefreshing = false

    /// User-ordered plugin IDs, best first. Drives source priority in the playback registry.
    public private(set) var orderedPluginIDs: [String] = []

    /// Sort mode for enabled plugins.
    public var pluginSortMode: PluginSortMode = .manual

    /// Called whenever the installed/enabled list changes so the composition root can rebuild sources.
    public var onPluginsChanged: (() async -> Void)?

    private let client: RegistryClient
    private let storage: PluginStorage
    private let sortModeStorage: PluginSortModeStorage

    public init(
        client: RegistryClient = RegistryClient(),
        storage: PluginStorage = PluginStorage(),
        sortModeStorage: PluginSortModeStorage = PluginSortModeStorage()
    ) {
        self.client = client
        self.storage = storage
        self.sortModeStorage = sortModeStorage
    }

    // MARK: - Lifecycle

    /// Loads installed plugins from disk. Call once at launch.
    public func load() async {
        let span = CisumSignpost.lifecycle.begin("plugin-store-load")
        defer { CisumSignpost.lifecycle.end("plugin-store-load", state: span) }

        do {
            installed = try await storage.loadAll()
            PerfLog.info("PluginStore: loaded \(installed.count) installed plugins: \(installed.map { "\($0.id)(enabled=\($0.isEnabled))" })")
        } catch {
            PerfLog.error("PluginStore failed to load installed plugins: \(error)")
            installed = []
        }

        // Load persisted ordering (best-first). Any new plugin not yet in the list is appended.
        var savedOrder = await sortModeStorage.loadOrder()
        let installedIDs = installed.map(\.id)
        let savedSet = Set(savedOrder)
        savedOrder.append(contentsOf: installedIDs.filter { !savedSet.contains($0) })
        // Remove IDs no longer installed.
        savedOrder.removeAll { !installedIDs.contains($0) }
        orderedPluginIDs = savedOrder

        pluginSortMode = await sortModeStorage.loadSortMode()
        PerfLog.info("PluginStore: loaded order=\(orderedPluginIDs), sortMode=\(pluginSortMode)")
    }

    // MARK: - Catalog

    public func refreshCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }

        PerfLog.trace("PluginStore: refreshCatalog() starting")
        do {
            catalog = try await client.fetchCatalog()
            lastError = nil
            PerfLog.info("PluginStore: refreshCatalog() succeeded, \(catalog.count) entries")
        } catch is CancellationError {
            PerfLog.trace("PluginStore: refreshCatalog() cancelled (view dismissed)")
        } catch let error as URLError where error.code == .cancelled {
            PerfLog.trace("PluginStore: refreshCatalog() URLSession cancelled (view dismissed)")
        } catch {
            lastError = error.localizedDescription
            PerfLog.error("Plugin catalog refresh failed: \(error)")
        }
    }

    // MARK: - Install

    /// Downloads and installs a plugin from a registry listing.
    public func install(_ entry: RegistryEntry) async throws {
        let source = try await client.download(from: entry.downloadURL, expectedSize: entry.size)

        let plugin = InstalledPlugin(
            id: entry.id,
            name: entry.name,
            version: entry.version,
            source: source,
            author: entry.author,
            summary: entry.summary,
            labels: entry.labels,
            iconURL: entry.iconURL,
            downloadURL: entry.downloadURL,
            versionCode: entry.versionCode
        )

        try await add(plugin)
    }

    /// Installs a plugin from an arbitrary URL, for modules not listed in any registry.
    ///
    /// The id is not known until the module is loaded, so the URL's filename stands in until the
    /// runtime reports the module's own id. Nothing here inspects or executes the source — that
    /// happens in ProviderSDK, which this module deliberately cannot see.
    public func install(from url: URL) async throws {
        let source = try await client.download(from: url)
        let fallbackID = url.deletingPathExtension().lastPathComponent

        try await add(InstalledPlugin(
            id: fallbackID,
            name: fallbackID,
            version: "",
            source: source,
            downloadURL: url
        ))
    }

    /// Re-downloads a plugin from where it came from.
    public func update(_ id: String) async throws {
        guard let existing = installed.first(where: { $0.id == id }) else {
            throw PluginError.notInstalled(id: id)
        }
        guard let url = existing.downloadURL else { return }

        var updated = existing
        updated.source = try await client.download(from: url)

        // Settings and enabled state survive an update; they are the user's, not the plugin's.
        if let listing = catalog.first(where: { $0.id == id }) {
            updated.version = listing.version
            updated.versionCode = listing.versionCode
            updated.name = listing.name
            updated.labels = listing.labels
        }

        try await add(updated)
    }

    /// Whether the registry lists a newer version than the one installed.
    ///
    /// Compares `versionCode`, not the display `version` string, which is not reliably ordered
    /// (`"v3.8.3"`, `"3.2.0"`, `""` all appear in the live registry).
    public func hasUpdate(_ plugin: InstalledPlugin) -> Bool {
        guard let listing = catalog.first(where: { $0.id == plugin.id }) else { return false }
        return listing.versionCode > plugin.versionCode
    }

    // MARK: - Manage

    public func setEnabled(_ enabled: Bool, for id: String) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].isEnabled = enabled
        PerfLog.info("PluginStore: setEnabled(\(enabled)) for \(id)")
        await persist(installed[index])
        await onPluginsChanged?()
    }

    public func setSetting(_ value: String, key: String, for id: String) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].settings[key] = value
        await persist(installed[index])
    }

    public func remove(_ id: String) async {
        installed.removeAll { $0.id == id }
        orderedPluginIDs.removeAll { $0 == id }
        await sortModeStorage.saveOrder(orderedPluginIDs)
        do {
            try await storage.delete(id)
        } catch {
            PerfLog.error("Could not delete plugin \(id): \(error)")
        }
        await onPluginsChanged?()
    }

    // MARK: - The catalog seam

    //
    // What the composition root reads to build sources. Returning plain values, not something
    // executable, is the point: this module never learns what a MusicSource is.

    /// Installed and enabled, in user-preferred order.
    public func enabled() -> [InstalledPlugin] {
        let enabledPlugins = installed.filter(\.isEnabled)
        PerfLog.info("PluginStore.enabled(): \(enabledPlugins.count) of \(installed.count) enabled: \(enabledPlugins.map(\.id))")

        switch pluginSortMode {
        case .manual:
            // Sort by the user's orderedPluginIDs (best first).
            return enabledPlugins.sorted { lhs, rhs in
                let lhsIndex = orderedPluginIDs.firstIndex(of: lhs.id) ?? Int.max
                let rhsIndex = orderedPluginIDs.firstIndex(of: rhs.id) ?? Int.max
                return lhsIndex < rhsIndex
            }
        case .quality:
            // Sort by quality label descending (Hi-Res > Lossless > High > Standard).
            return enabledPlugins.sorted { lhs, rhs in
                qualityRank(lhs.settings["quality"] ?? "") > qualityRank(rhs.settings["quality"] ?? "")
            }
        case .speed:
            // Sort by average latency ascending (fastest first).
            return enabledPlugins.sorted { lhs, rhs in
                let lhsLatency = Double(lhs.settings["avgLatencyMs"] ?? "") ?? Double.greatestFiniteMagnitude
                let rhsLatency = Double(rhs.settings["avgLatencyMs"] ?? "") ?? Double.greatestFiniteMagnitude
                return lhsLatency < rhsLatency
            }
        }
    }

    /// Move installed plugins within the list (drag-to-reorder).
    public func moveInstalled(from source: IndexSet, to destination: Int) {
        installed.move(fromOffsets: source, toOffset: destination)
        orderedPluginIDs = installed.map(\.id)
        Task {
            await sortModeStorage.saveOrder(orderedPluginIDs)
        }
    }

    /// Set the sort mode for enabled plugins.
    public func setSortMode(_ mode: PluginSortMode) async {
        pluginSortMode = mode
        await sortModeStorage.saveSortMode(mode)
        await onPluginsChanged?()
    }

    private func qualityRank(_ quality: String) -> Int {
        let q = quality.uppercased()
        if q.contains("HI-RES") || q.contains("24-BIT") {
            return 4
        }
        if q.contains("LOSSLESS") || q.contains("FLAC") {
            return 3
        }
        if q.contains("HIGH") || q.contains("320") {
            return 2
        }
        return 1
    }

    // MARK: - Private

    private func add(_ plugin: InstalledPlugin) async throws {
        try await storage.save(plugin)
        let isNew = !installed.contains(where: { $0.id == plugin.id })
        if let index = installed.firstIndex(where: { $0.id == plugin.id }) {
            installed[index] = plugin
        } else {
            installed.insert(plugin, at: 0)
        }
        // Track newly-installed plugins in ordering (append to end = lowest priority).
        if isNew {
            orderedPluginIDs.append(plugin.id)
            await sortModeStorage.saveOrder(orderedPluginIDs)
        }
        await onPluginsChanged?()
    }

    private func persist(_ plugin: InstalledPlugin) async {
        do {
            try await storage.save(plugin)
        } catch {
            PerfLog.error("Could not persist plugin \(plugin.id): \(error)")
        }
    }
}
