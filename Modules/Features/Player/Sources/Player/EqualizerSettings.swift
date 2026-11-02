//
//  EqualizerSettings.swift
//  Player
//
//  The equalizer's stored settings and presets.
//

import Foundation
import Observation
import PlaybackCore

/// What the user set on the equalizer, persisted, and pushed to `Equalizer.shared` on every change.
@MainActor
@Observable
public final class EqualizerSettings {
    public static let shared = EqualizerSettings()

    public var isEnabled: Bool {
        didSet { save() }
    }

    /// dB per band, in `Equalizer.frequencies` order.
    public var gains: [Float] {
        didSet { save() }
    }

    /// The preset the gains match, or `nil` for a custom curve.
    public var preset: EqualizerPreset? {
        EqualizerPreset.allCases.first { $0.gains == gains }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        let stored = (defaults.array(forKey: Key.gains) as? [Double])?.map(Float.init)
        gains = stored?.count == Equalizer.frequencies.count ? stored! : EqualizerPreset.flat.gains
        Equalizer.shared.update(isEnabled: isEnabled, gains: gains)
    }

    private func save() {
        Equalizer.shared.update(isEnabled: isEnabled, gains: gains)
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(gains.map(Double.init), forKey: Key.gains)
    }

    private enum Key {
        static let enabled = "player.equalizer.enabled"
        static let gains = "player.equalizer.gains"
    }
}

/// Gains for 32 Hz … 16 kHz.
public enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, bassBoost, treble, vocal, loudness, acoustic, electronic

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Boost"
        case .treble: "Treble Boost"
        case .vocal: "Vocal"
        case .loudness: "Loudness"
        case .acoustic: "Acoustic"
        case .electronic: "Electronic"
        }
    }

    public var gains: [Float] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .treble: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .vocal: [-2, -2, -1, 0, 2, 4, 4, 2, 0, -1]
        case .loudness: [5, 4, 2, 0, -1, 0, -1, 1, 4, 5]
        case .acoustic: [4, 4, 3, 1, 2, 2, 3, 3, 3, 2]
        case .electronic: [4, 4, 1, 0, -2, 1, 0, 1, 4, 5]
        }
    }
}
