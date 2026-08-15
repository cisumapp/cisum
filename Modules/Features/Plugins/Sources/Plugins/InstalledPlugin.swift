//
//  InstalledPlugin.swift
//  Plugins
//
//  What a plugin is, from the catalog's point of view.
//

import Foundation

/// A plugin the user has installed.
///
/// **This type deliberately knows nothing about `ProviderSDK`.** It is a plain value: identity,
/// provenance, source text, and the user's choices. Turning it into something executable is the
/// composition root's job, via a small adapter onto `ProviderSDK.PluginBundle`.
///
/// That indirection is the whole reason `Plugins` and `ProviderSDK` can be developed, tested, and
/// reasoned about separately — and `scripts/check-boundaries.sh` fails the build if either starts
/// importing the other.
public struct InstalledPlugin: Sendable, Identifiable, Equatable, Codable {
    /// The plugin's own identifier, as declared by the module and by the registry.
    public let id: String

    public var name: String
    public var version: String
    public var author: String?
    public var summary: String?

    /// UI tags from the registry, e.g. `["LOSSLESS", "HI-RES"]`.
    public var labels: [String]

    /// Icon URL from the registry, keyed `logo` in module metadata.
    public var iconURL: URL?

    /// Where this plugin was downloaded from, so it can be updated in place.
    public var downloadURL: URL?

    /// Integer version used for update comparison. The registry's `code` field; `version` is only
    /// for display and is not reliably ordered.
    public var versionCode: Int

    /// Whether the user has this plugin turned on.
    public var isEnabled: Bool

    /// The user's chosen values for the plugin's settings, keyed by setting name.
    public var settings: [String: String]

    public var installedAt: Date

    /// The raw module text.
    ///
    /// Stored separately from this record on disk — see `PluginStore` — because it is large
    /// relative to the metadata and the metadata is what gets listed and filtered.
    public var source: String

    public init(
        id: String,
        name: String,
        version: String,
        source: String,
        author: String? = nil,
        summary: String? = nil,
        labels: [String] = [],
        iconURL: URL? = nil,
        downloadURL: URL? = nil,
        versionCode: Int = 0,
        isEnabled: Bool = true,
        settings: [String: String] = [:],
        installedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.source = source
        self.author = author
        self.summary = summary
        self.labels = labels
        self.iconURL = iconURL
        self.downloadURL = downloadURL
        self.versionCode = versionCode
        self.isEnabled = isEnabled
        self.settings = settings
        self.installedAt = installedAt
    }
}
