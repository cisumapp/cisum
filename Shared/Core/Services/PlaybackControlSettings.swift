import Foundation
import SwiftUI

@Observable
@MainActor
final class PlaybackControlSettings {
    static let shared = PlaybackControlSettings()

    private enum Keys {
        static let volumeButtonHoldSkipEnabled = "playback.controls.volume.holdSkip.enabled"
        static let volumeButtonHoldThreshold = "playback.controls.volume.holdSkip.threshold"
        static let volumeButtonHoldRepeatInterval = "playback.controls.volume.holdSkip.repeatInterval"
        static let volumeButtonHoldReleaseTimeout = "playback.controls.volume.holdSkip.releaseTimeout"
        static let volumeButtonHoldRestoreVolume = "playback.controls.volume.holdSkip.restoreVolume"
        static let volumeButtonHoldUpSkipsForward = "playback.controls.volume.holdSkip.upSkipsForward"
    }

    private let defaults: UserDefaults
    private let persistenceScheduler = DebouncedWorkScheduler(delay: .milliseconds(250))

    var volumeButtonHoldSkipEnabled: Bool {
        didSet { schedulePersistence() }
    }

    var volumeButtonHoldThreshold: Double {
        didSet { schedulePersistence() }
    }

    var volumeButtonHoldRepeatInterval: Double {
        didSet { schedulePersistence() }
    }

    var volumeButtonHoldReleaseTimeout: Double {
        didSet { schedulePersistence() }
    }

    var volumeButtonHoldRestoreVolume: Bool {
        didSet { schedulePersistence() }
    }

    var volumeButtonHoldUpSkipsForward: Bool {
        didSet { schedulePersistence() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.volumeButtonHoldSkipEnabled = defaults.object(forKey: Keys.volumeButtonHoldSkipEnabled) as? Bool ?? true
        self.volumeButtonHoldThreshold = defaults.object(forKey: Keys.volumeButtonHoldThreshold) as? Double ?? 0.8
        self.volumeButtonHoldRepeatInterval = defaults.object(forKey: Keys.volumeButtonHoldRepeatInterval) as? Double ?? 0.5
        self.volumeButtonHoldReleaseTimeout = defaults.object(forKey: Keys.volumeButtonHoldReleaseTimeout) as? Double ?? 0.18
        self.volumeButtonHoldRestoreVolume = defaults.object(forKey: Keys.volumeButtonHoldRestoreVolume) as? Bool ?? true
        self.volumeButtonHoldUpSkipsForward = defaults.object(forKey: Keys.volumeButtonHoldUpSkipsForward) as? Bool ?? true
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
        defaults.set(volumeButtonHoldSkipEnabled, forKey: Keys.volumeButtonHoldSkipEnabled)
        defaults.set(volumeButtonHoldThreshold, forKey: Keys.volumeButtonHoldThreshold)
        defaults.set(volumeButtonHoldRepeatInterval, forKey: Keys.volumeButtonHoldRepeatInterval)
        defaults.set(volumeButtonHoldReleaseTimeout, forKey: Keys.volumeButtonHoldReleaseTimeout)
        defaults.set(volumeButtonHoldRestoreVolume, forKey: Keys.volumeButtonHoldRestoreVolume)
        defaults.set(volumeButtonHoldUpSkipsForward, forKey: Keys.volumeButtonHoldUpSkipsForward)
    }
}
