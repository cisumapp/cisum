//
//  RegistryModels.swift
//  Plugins
//
//  The shape of https://8spine-modules.vercel.app/index.json and its federated sources.
//

import Foundation

/// One plugin as listed in a registry index.
///
/// The registry serves two entry variants that differ in small, annoying ways: locally-hosted
/// entries use a **relative** `download` path and tag with `tags`, while entries federated in from
/// an external source use an **absolute** `download` URL and tag with `labels`. Both are decoded
/// into this one type so nothing downstream has to care.
public struct RegistryEntry: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let author: String?
    public let summary: String?

    /// Display version, e.g. `"v3.8.3"`. Not reliably ordered — compare `versionCode` instead.
    public let version: String

    /// Integer version for update checks. The registry's `code` field.
    public let versionCode: Int

    /// Fully resolved download URL. Relative paths are joined against the registry's base before
    /// this type is constructed, so consumers always get something fetchable.
    public let downloadURL: URL

    /// Expected byte count. The only integrity signal the registry offers.
    public let size: Int?

    /// `MODULE`, `STREAM`, `CONNECTOR`, or `ARTWORK`.
    public let type: String

    public let labels: [String]
    public let iconURL: URL?

    /// Registry-declared trust. **Advisory only.**
    ///
    /// There are no hashes and no signatures anywhere in the registry, so this flag is a
    /// curator's opinion and nothing more. Every module is executed as untrusted code regardless.
    public let isTrusted: Bool
    public let isFeatured: Bool
    public let isNSFW: Bool

    /// Which category or external source this came from, for grouping in the UI.
    public let category: String

    public init(
        id: String, name: String, author: String?, summary: String?,
        version: String, versionCode: Int, downloadURL: URL, size: Int?,
        type: String, labels: [String], iconURL: URL?,
        isTrusted: Bool, isFeatured: Bool, isNSFW: Bool, category: String
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.summary = summary
        self.version = version
        self.versionCode = versionCode
        self.downloadURL = downloadURL
        self.size = size
        self.type = type
        self.labels = labels
        self.iconURL = iconURL
        self.isTrusted = isTrusted
        self.isFeatured = isFeatured
        self.isNSFW = isNSFW
        self.category = category
    }
}

/// Another registry federated into this one.
///
/// The index carries an `external_sources` array; each entry names a foreign index to fetch and
/// merge under `category:<key>`. Three are live in the default registry, hosted on GitHub raw and
/// on independent domains.
public struct ExternalSource: Sendable, Equatable {
    public let key: String
    public let title: String
    /// The foreign index to fetch (`index.json` or `source.json`).
    public let url: URL
    /// Base for resolving that index's relative download paths.
    ///
    /// Note this lives on the **registry entry**, not in the module — modules carry no base URL.
    public let baseURL: URL?
}

/// Decodes registry indexes. Tolerant by design: a malformed entry is skipped, not fatal.
public enum RegistryDecoder {
    /// Parses an index document.
    ///
    /// - Parameter base: Used to resolve relative `download` paths.
    /// - Returns: The entries found, plus any external sources to federate in.
    public static func decode(
        _ data: Data,
        base: URL
    ) -> (entries: [RegistryEntry], externalSources: [ExternalSource]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }

        var entries: [RegistryEntry] = []
        var externals: [ExternalSource] = []

        for (key, value) in root {
            if key == "external_sources" {
                externals = (value as? [[String: Any]] ?? []).compactMap(externalSource(from:))
                continue
            }

            // Categories appear as "category:modules", "category:geolier_modules", … and older
            // indexes use bare keys like "modules". Any array of objects is treated as a category.
            guard let rows = value as? [[String: Any]] else { continue }
            let category = key.hasPrefix("category:") ? String(key.dropFirst("category:".count)) : key

            entries.append(contentsOf: rows.compactMap { entry(from: $0, category: category, base: base) })
        }

        return (entries, externals)
    }

    static func entry(from json: [String: Any], category: String, base: URL) -> RegistryEntry? {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }

        // Absolute for federated entries, relative for local ones.
        guard let rawDownload = (json["download"] as? String) ?? (json["file"] as? String),
              let downloadURL = resolve(rawDownload, against: base, folder: json["folder"] as? String)
        else { return nil }

        return RegistryEntry(
            id: id,
            name: json["name"] as? String ?? id,
            author: json["author"] as? String,
            summary: json["description"] as? String,
            version: json["version"] as? String ?? "",
            versionCode: json["code"] as? Int ?? 0,
            downloadURL: downloadURL,
            size: json["size"] as? Int,
            type: json["type"] as? String ?? "MODULE",
            // `labels` on federated entries, `tags` on local ones.
            labels: (json["labels"] as? [String]) ?? (json["tags"] as? [String]) ?? [],
            iconURL: (json["logo"] as? String).flatMap { URL(string: $0) },
            isTrusted: json["trusted"] as? Bool ?? false,
            isFeatured: json["featured"] as? Bool ?? false,
            isNSFW: json["nsfw"] as? Bool ?? false,
            category: category
        )
    }

    static func externalSource(from json: [String: Any]) -> ExternalSource? {
        guard let key = json["key"] as? String,
              let urlString = json["url"] as? String,
              let url = URL(string: urlString)
        else { return nil }

        return ExternalSource(
            key: key,
            title: json["title"] as? String ?? key,
            url: url,
            baseURL: (json["baseUrl"] as? String).flatMap { URL(string: $0) }
        )
    }

    /// Resolves a download reference, which may be absolute or relative to the registry.
    static func resolve(_ path: String, against base: URL, folder: String?) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        // Older indexes give a bare `file` plus a separate `folder`.
        let relative = path.contains("/") ? path : [folder, path].compactMap(\.self).joined(separator: "/")
        return URL(string: relative, relativeTo: base)?.absoluteURL
    }
}
