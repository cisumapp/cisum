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

    private let client: RegistryClient
    private let storage: PluginStorage

    public init(client: RegistryClient = RegistryClient(), storage: PluginStorage = PluginStorage()) {
        self.client = client
        self.storage = storage
    }

    // MARK: - Lifecycle

    /// Loads installed plugins from disk. Call once at launch.
    public func load() async {
        let span = CisumSignpost.lifecycle.begin("plugin-store-load")
        defer { CisumSignpost.lifecycle.end("plugin-store-load", state: span) }

        do {
            installed = try await storage.loadAll()
        } catch {
            PerfLog.error("PluginStore failed to load installed plugins: \(error)")
            installed = []
        }
    }

    // MARK: - Catalog

    public func refreshCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            catalog = try await client.fetchCatalog()
            lastError = nil
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
        await persist(installed[index])
    }

    public func setSetting(_ value: String, key: String, for id: String) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].settings[key] = value
        await persist(installed[index])
    }

    public func remove(_ id: String) async {
        installed.removeAll { $0.id == id }
        do {
            try await storage.delete(id)
        } catch {
            PerfLog.error("Could not delete plugin \(id): \(error)")
        }
    }

    // MARK: - The catalog seam
    //
    // What the composition root reads to build sources. Returning plain values, not something
    // executable, is the point: this module never learns what a MusicSource is.

    /// Installed and enabled, in install order.
    public func enabled() -> [InstalledPlugin] {
        installed.filter(\.isEnabled)
    }

    // MARK: - Private

    private func add(_ plugin: InstalledPlugin) async throws {
        try await storage.save(plugin)
        if let index = installed.firstIndex(where: { $0.id == plugin.id }) {
            installed[index] = plugin
        } else {
            installed.insert(plugin, at: 0)
        }
    }

    private func persist(_ plugin: InstalledPlugin) async {
        do {
            try await storage.save(plugin)
        } catch {
            PerfLog.error("Could not persist plugin \(plugin.id): \(error)")
        }
    }
}
