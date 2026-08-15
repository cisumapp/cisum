//
//  PluginCatalogAdapter.swift
//  Core
//
//  The one place that knows both Plugins and ProviderSDK exist.
//

import Foundation
import Plugins
import ProviderSDK
import Utilities

/// Bridges the app's plugin catalog to ProviderSDK's expectation of one.
///
/// **This adapter is the decoupling.** `Plugins` vends `InstalledPlugin` and has never heard of
/// `MusicSource`; `ProviderSDK` declares `PluginCatalog` and has never heard of a plugin store.
/// Neither imports the other, which `scripts/check-boundaries.sh` enforces. The cost is one small
/// struct here, and the benefit is that either side can be rewritten without touching the other.
struct PluginCatalogAdapter: PluginCatalog {
    let store: PluginStore

    func enabledPlugins() async -> [PluginBundle] {
        await MainActor.run {
            store.enabled().map { plugin in
                PluginBundle(id: plugin.id, source: plugin.source, settings: plugin.settings)
            }
        }
    }
}

/// Loads the user's enabled plugins into playable sources.
///
/// Failures are surfaced rather than swallowed: one expired or broken plugin must not take search
/// down for the rest, and the user needs to know which of theirs stopped working.
@MainActor
enum SourceBuilder {
    static func buildSources(from store: PluginStore) async -> [any MusicSource] {
        let adapter = PluginCatalogAdapter(store: store)
        let (sources, failures) = await SourceLoader.loadAll(from: adapter)

        for failure in failures {
            PerfLog.error("Plugin \(failure.id) failed to load: \(failure.error.localizedDescription)")
        }

        return sources
    }
}
