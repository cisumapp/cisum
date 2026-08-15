//
//  PluginStorage.swift
//  Plugins
//
//  Where installed plugins live on disk.
//

import Foundation

/// Persists installed plugins.
///
/// Metadata and module source are stored separately: one small JSON index that is read on every
/// launch to populate the list, and one file per plugin holding its source. Modules run from
/// 7 KB to 29 KB, so keeping them out of the index means launch reads a couple of kilobytes
/// instead of hundreds, and only the plugins actually enabled get their source read at all.
public actor PluginStorage {
    private let directory: URL
    private let indexURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cisum/Plugins", isDirectory: true)

        self.directory = base
        indexURL = base.appendingPathComponent("index.json")
    }

    /// Loads every installed plugin, source included.
    public func loadAll() throws -> [InstalledPlugin] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }

        let data = try Data(contentsOf: indexURL)
        let records = try JSONDecoder().decode([InstalledPlugin].self, from: data)

        // The index stores metadata with an empty `source`; fill each one in from its own file.
        return records.map { record in
            var plugin = record
            plugin.source = (try? String(contentsOf: sourceURL(for: record.id), encoding: .utf8)) ?? ""
            return plugin
        }
        // A plugin whose source file vanished is not usable and would fail confusingly later.
        .filter { !$0.source.isEmpty }
    }

    public func save(_ plugin: InstalledPlugin) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try plugin.source.write(to: sourceURL(for: plugin.id), atomically: true, encoding: .utf8)

        var records = (try? loadIndex()) ?? []
        var stripped = plugin
        stripped.source = ""   // source lives in its own file, never duplicated in the index

        if let existing = records.firstIndex(where: { $0.id == plugin.id }) {
            records[existing] = stripped
        } else {
            records.insert(stripped, at: 0)
        }

        try writeIndex(records)
    }

    public func delete(_ id: String) throws {
        try? FileManager.default.removeItem(at: sourceURL(for: id))
        let records = ((try? loadIndex()) ?? []).filter { $0.id != id }
        try writeIndex(records)
    }

    // MARK: - Private

    private func loadIndex() throws -> [InstalledPlugin] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([InstalledPlugin].self, from: Data(contentsOf: indexURL))
    }

    private func writeIndex(_ records: [InstalledPlugin]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: indexURL, options: .atomic)
    }

    /// A plugin id comes from a third-party registry, so it is sanitised before being used as a
    /// filename — an id containing `../` would otherwise write outside the plugins directory.
    private func sourceURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return directory.appendingPathComponent("\(safe).module")
    }
}
