//
//  PluginSortMode.swift
//  Plugins
//
//  How enabled plugins are ordered for playback priority.
//

import Foundation

/// Controls the order of enabled plugins when building the source registry.
public enum PluginSortMode: String, CaseIterable, Codable, Sendable {
    /// User manually reorders plugins via drag-and-drop.
    case manual
    /// Sort by audio quality descending (Hi-Res > Lossless > High > Standard).
    case quality
    /// Sort by average response latency ascending (fastest first).
    case speed

    public var displayName: String {
        switch self {
        case .manual: "By Preference"
        case .quality: "By Quality"
        case .speed: "By Speed"
        }
    }

    public var systemImage: String {
        switch self {
        case .manual: "hand.point.up.left"
        case .quality: "hifispeaker.fill"
        case .speed: "bolt.fill"
        }
    }
}

/// Persists sort mode and plugin ordering to UserDefaults (app group compatible).
public actor PluginSortModeStorage {
    private let defaults: UserDefaults
    private let orderKey = "plugin_order"
    private let sortModeKey = "plugin_sort_mode"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadOrder() -> [String] {
        defaults.stringArray(forKey: orderKey) ?? []
    }

    public func saveOrder(_ ids: [String]) {
        defaults.set(ids, forKey: orderKey)
    }

    public func loadSortMode() -> PluginSortMode {
        let raw = defaults.string(forKey: sortModeKey) ?? ""
        return PluginSortMode(rawValue: raw) ?? .manual
    }

    public func saveSortMode(_ mode: PluginSortMode) {
        defaults.set(mode.rawValue, forKey: sortModeKey)
    }
}
