//
//  PlaybackControlSettings.swift
//  Player
//
//  User preferences for playback controls.
//

import Foundation
import Observation
import Utilities

/// Playback control preferences, backed by `UserDefaults`.
///
/// Writes are debounced. These are bound to sliders in Settings, so a drag produces a value change
/// per frame; writing each one straight through would mean roughly sixty synchronous
/// `UserDefaults` writes a second while the user's finger is down.
@MainActor
@Observable
public final class PlaybackControlSettings {
    public static let shared = PlaybackControlSettings()

    /// Whether holding a volume button skips tracks instead of changing volume.
    public var volumeButtonHoldSkipEnabled: Bool {
        didSet { scheduleWrite() }
    }

    /// How long the button must be held before it counts as a skip, in seconds.
    public var volumeButtonHoldThreshold: Double {
        didSet { scheduleWrite() }
    }

    /// Interval between repeat skips while the button stays held.
    public var volumeButtonHoldRepeatInterval: Double {
        didSet { scheduleWrite() }
    }

    /// How long to wait after release before treating the gesture as finished.
    public var volumeButtonHoldReleaseTimeout: Double {
        didSet { scheduleWrite() }
    }

    /// Whether to restore the pre-gesture volume afterwards.
    public var volumeButtonHoldRestoreVolume: Bool {
        didSet { scheduleWrite() }
    }

    /// Whether volume-up skips forward (rather than back).
    public var volumeButtonHoldUpSkipsForward: Bool {
        didSet { scheduleWrite() }
    }

    private let defaults: UserDefaults
    private var writeTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `object(forKey:)` first, because `bool(forKey:)` cannot distinguish "false" from "never
        // set" — and the sensible default for two of these is true.
        self.volumeButtonHoldSkipEnabled = defaults.object(forKey: Key.skipEnabled) as? Bool ?? false
        self.volumeButtonHoldThreshold = defaults.object(forKey: Key.threshold) as? Double ?? 0.6
        self.volumeButtonHoldRepeatInterval = defaults.object(forKey: Key.repeatInterval) as? Double ?? 0.5
        self.volumeButtonHoldReleaseTimeout = defaults.object(forKey: Key.releaseTimeout) as? Double ?? 0.35
        self.volumeButtonHoldRestoreVolume = defaults.object(forKey: Key.restoreVolume) as? Bool ?? true
        self.volumeButtonHoldUpSkipsForward = defaults.object(forKey: Key.upSkipsForward) as? Bool ?? true
    }

    /// Writes any pending changes immediately.
    ///
    /// Called when the app backgrounds, since a debounced write scheduled a moment earlier would
    /// otherwise be lost if the process is suspended before it fires.
    public func flushPendingWrites() {
        writeTask?.cancel()
        writeTask = nil
        write()
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        defaults.set(volumeButtonHoldSkipEnabled, forKey: Key.skipEnabled)
        defaults.set(volumeButtonHoldThreshold, forKey: Key.threshold)
        defaults.set(volumeButtonHoldRepeatInterval, forKey: Key.repeatInterval)
        defaults.set(volumeButtonHoldReleaseTimeout, forKey: Key.releaseTimeout)
        defaults.set(volumeButtonHoldRestoreVolume, forKey: Key.restoreVolume)
        defaults.set(volumeButtonHoldUpSkipsForward, forKey: Key.upSkipsForward)
    }

    private enum Key {
        static let skipEnabled = "player.volumeHold.skipEnabled"
        static let threshold = "player.volumeHold.threshold"
        static let repeatInterval = "player.volumeHold.repeatInterval"
        static let releaseTimeout = "player.volumeHold.releaseTimeout"
        static let restoreVolume = "player.volumeHold.restoreVolume"
        static let upSkipsForward = "player.volumeHold.upSkipsForward"
    }
}
