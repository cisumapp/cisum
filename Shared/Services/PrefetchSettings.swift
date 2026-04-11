import SwiftUI

enum PrefetchModeOverride: String, CaseIterable, Identifiable {
    case auto
    case metadataOnly
    case aggressiveWarmup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .metadataOnly: return "Metadata Only"
        case .aggressiveWarmup: return "Aggressive Warmup"
        }
    }
}

@Observable
@MainActor
final class PrefetchSettings {
    static let shared = PrefetchSettings()

    private enum Keys {
        static let adaptiveEnabled = "prefetch.adaptive.enabled"
        static let modeOverride = "prefetch.mode.override"
        static let wifiCount = "prefetch.wifi.count"
        static let cellularCount = "prefetch.cellular.count"
        static let wifiConcurrency = "prefetch.wifi.concurrency"
        static let cellularConcurrency = "prefetch.cellular.concurrency"
        static let metricsEnabled = "prefetch.metrics.enabled"
        static let suggestionPipelineEnabled = "prefetch.suggestions.pipeline.enabled"
    }

    private let defaults: UserDefaults
    private let persistenceScheduler = DebouncedWorkScheduler(delay: .milliseconds(250))

    var adaptivePrefetchEnabled: Bool {
        didSet { schedulePersistence() }
    }

    var prefetchModeOverride: PrefetchModeOverride {
        didSet { schedulePersistence() }
    }

    var wifiPrefetchCount: Int {
        didSet { schedulePersistence() }
    }

    var cellularPrefetchCount: Int {
        didSet { schedulePersistence() }
    }

    var wifiPrefetchConcurrency: Int {
        didSet { schedulePersistence() }
    }

    var cellularPrefetchConcurrency: Int {
        didSet { schedulePersistence() }
    }

    var metricsEnabled: Bool {
        didSet { schedulePersistence() }
    }

    var suggestionPipelineEnabled: Bool {
        didSet { schedulePersistence() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.adaptivePrefetchEnabled = defaults.object(forKey: Keys.adaptiveEnabled) as? Bool ?? true

        let savedMode = defaults.string(forKey: Keys.modeOverride) ?? PrefetchModeOverride.auto.rawValue
        self.prefetchModeOverride = PrefetchModeOverride(rawValue: savedMode) ?? .auto

        self.wifiPrefetchCount = defaults.object(forKey: Keys.wifiCount) as? Int ?? 6
        self.cellularPrefetchCount = defaults.object(forKey: Keys.cellularCount) as? Int ?? 2
        self.wifiPrefetchConcurrency = defaults.object(forKey: Keys.wifiConcurrency) as? Int ?? 3
        self.cellularPrefetchConcurrency = defaults.object(forKey: Keys.cellularConcurrency) as? Int ?? 1
        self.metricsEnabled = defaults.object(forKey: Keys.metricsEnabled) as? Bool ?? true
        self.suggestionPipelineEnabled = defaults.object(forKey: Keys.suggestionPipelineEnabled) as? Bool ?? true
    }

    func flushPendingWrites() {
        persistenceScheduler.cancel()
        persistToDefaults()
    }

    private func schedulePersistence() {
        persistenceScheduler.schedule { [weak self] in
            self?.persistToDefaults()
        }
    }

    private func persistToDefaults() {
        defaults.set(adaptivePrefetchEnabled, forKey: Keys.adaptiveEnabled)
        defaults.set(prefetchModeOverride.rawValue, forKey: Keys.modeOverride)
        defaults.set(wifiPrefetchCount, forKey: Keys.wifiCount)
        defaults.set(cellularPrefetchCount, forKey: Keys.cellularCount)
        defaults.set(wifiPrefetchConcurrency, forKey: Keys.wifiConcurrency)
        defaults.set(cellularPrefetchConcurrency, forKey: Keys.cellularConcurrency)
        defaults.set(metricsEnabled, forKey: Keys.metricsEnabled)
        defaults.set(suggestionPipelineEnabled, forKey: Keys.suggestionPipelineEnabled)
    }
}
