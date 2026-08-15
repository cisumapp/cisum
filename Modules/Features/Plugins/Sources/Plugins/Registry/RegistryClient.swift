//
//  RegistryClient.swift
//  Plugins
//
//  Fetching the plugin catalog, including registries federated in from other people's servers.
//

import Foundation

/// Fetches plugin listings and downloads module source.
public actor RegistryClient {
    /// The default registry. Users can point at any index that follows the same shape.
    public static let defaultRegistry = URL(string: "https://8spine-modules.vercel.app/")!

    private let session: URLSession
    private let registry: URL

    public init(registry: URL = RegistryClient.defaultRegistry, session: URLSession = .shared) {
        self.registry = registry
        self.session = session
    }

    /// Fetches the index and everything it federates.
    ///
    /// `/index.json` is the canonical document. (`/modules.json` also responds but is an older
    /// schema listing a different, non-overlapping set; `/api/modules` and `/modules` 404.)
    ///
    /// External sources are fetched concurrently and merged. A source that is down is skipped
    /// rather than failing the whole listing — they are other people's servers, and one being
    /// unreachable must not empty the user's catalog.
    public func fetchCatalog() async throws -> [RegistryEntry] {
        let indexURL = registry.appendingPathComponent("index.json")
        let (data, _) = try await session.data(from: indexURL)

        let (entries, externals) = RegistryDecoder.decode(data, base: registry)

        let federated = await withTaskGroup(of: [RegistryEntry].self) { group in
            for source in externals {
                group.addTask { [session] in
                    guard let (data, _) = try? await session.data(from: source.url) else { return [] }
                    let base = source.baseURL ?? source.url.deletingLastPathComponent()
                    let (rows, _) = RegistryDecoder.decode(data, base: base)
                    // Foreign indexes label their own categories; re-key them under the source so
                    // the UI can group by where a plugin came from.
                    return rows.map { row in
                        RegistryEntry(
                            id: row.id, name: row.name, author: row.author, summary: row.summary,
                            version: row.version, versionCode: row.versionCode,
                            downloadURL: row.downloadURL, size: row.size, type: row.type,
                            labels: row.labels, iconURL: row.iconURL,
                            isTrusted: row.isTrusted, isFeatured: row.isFeatured, isNSFW: row.isNSFW,
                            category: source.key
                        )
                    }
                }
            }

            var collected: [RegistryEntry] = []
            for await rows in group { collected.append(contentsOf: rows) }
            return collected
        }

        // Later entries lose to earlier ones on id collision, so the primary registry wins over a
        // federated source that happens to reuse an id.
        var seen = Set<String>()
        return (entries + federated).filter { seen.insert($0.id).inserted }
    }

    /// Downloads a plugin's module source.
    ///
    /// - Parameter expectedSize: If the registry declared a byte count, it is checked. This is the
    ///   **only** integrity signal available — the registry publishes no hashes and no signatures,
    ///   so a match means "not truncated", never "not tampered with". Modules are executed as
    ///   untrusted code regardless of what the registry claims about them.
    public func download(from url: URL, expectedSize: Int? = nil) async throws -> String {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw PluginError.downloadFailed(url: url, status: http.statusCode)
        }
        if let expectedSize, data.count != expectedSize {
            throw PluginError.sizeMismatch(expected: expectedSize, actual: data.count)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw PluginError.notText(url: url)
        }
        return source
    }
}

public enum PluginError: Error, Sendable, Equatable {
    case downloadFailed(url: URL, status: Int)
    case sizeMismatch(expected: Int, actual: Int)
    case notText(url: URL)
    case notInstalled(id: String)
}

extension PluginError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .downloadFailed(url, status):
            "Could not download the plugin from \(url.host() ?? url.absoluteString) (HTTP \(status))."
        case let .sizeMismatch(expected, actual):
            "The downloaded plugin was \(actual) bytes but the registry expected \(expected). It may be corrupt."
        case let .notText(url):
            "The file at \(url.lastPathComponent) is not readable as text, so it is not a plugin."
        case let .notInstalled(id):
            "Plugin \(id) is not installed."
        }
    }
}
