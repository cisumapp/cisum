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
            let enabled = store.enabled()
            let bundles = enabled.map { plugin in
                PluginBundle(id: plugin.id, source: plugin.source, settings: plugin.settings)
            }
            PerfLog.info("PluginCatalogAdapter: enabledPlugins() returning \(bundles.count) bundles: \(bundles.map(\.id))")
            return bundles
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
        PerfLog.info("SourceBuilder.buildSources(): starting — loading sources from enabled plugins")
        let adapter = PluginCatalogAdapter(store: store)
        let enabled = await adapter.enabledPlugins().map(\.id)
        let (sources, failures) = await SourceLoader.loadAll(from: adapter)

        PerfLog.info("SourceBuilder.buildSources(): loaded \(sources.count) sources: \(sources.map { "\($0.id) caps=\($0.capabilities)" })")
        for failure in failures {
            PerfLog.error("Plugin \(failure.id) failed to load: \(failure.error.localizedDescription)")
        }

        // **Enabled is not loaded.** A plugin the user switched on and which cisum could not run is the
        // one state the user cannot see from the Plugins screen, and it is the state that used to be
        // reported by a pair of lines a hundred apart ("enabled plugins: …" then "failed to load:").
        // Saying both numbers in one place is what makes "7 enabled, 3 loaded" a diagnosis rather
        // than an arithmetic exercise. Nothing here changes the outcome: a plugin that fails is still
        // simply absent from the registry, which is what keeps the others working.
        let unavailable = enabled.filter { id in failures.contains { $0.id == id } }
        if unavailable.isEmpty {
            PerfLog.info("SourceBuilder.buildSources(): all \(enabled.count) enabled plugin(s) are loaded")
        } else {
            PerfLog.warning(
                "SourceBuilder.buildSources(): \(unavailable.count) of \(enabled.count) enabled plugin(s)"
                    + " could not be loaded and will not be searched or played from: \(unavailable)"
            )
        }

        return sources
    }
}
