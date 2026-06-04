//
//  CisumSignposter.swift
//  cisum
//
//  Created by Antigravity on 31/05/26.
//
//  PURPOSE
//  -------
//  Single source-of-truth for all os_log / os_signpost integration in cisum.
//  Every subsystem gets a typed OSLog.Logger + an OSSignposter so Instruments
//  (Time Profiler, Hangs, Swift Concurrency, App Launch) can filter by category.
//
//  USAGE
//  -----
//  import Utilities
//
//  // Structured logging (visible in Console.app + Instruments):
//  CisumLog.playback.info("Starting playback for id=\(id, privacy: .public)")
//
//  // Interval spans visible in Instruments → Points of Interest:
//  let state = CisumSignpost.playback.begin("stream-resolve")
//  defer { CisumSignpost.playback.end("stream-resolve", state: state) }
//
//  // Convenience tracing helper:
//  await CisumSignpost.playback.traceAsync("tap-to-play") { await doWork() }

import Foundation
import os.log
import os.signpost

// MARK: - Subsystem constant

private let kSubsystem = "aaravgupta.cisum"

// MARK: - Typed Logger namespace

//
// NOTE: We use the full type name `os.Logger` / `OSLog.Logger` throughout
// because `Utilities` already declares a custom `enum Logger { … }`.
// Clients that import Utilities must use `CisumLog.<category>` rather than
// constructing loggers directly.

/// Namespace for all `os.Logger` instances used across the cisum codebase.
/// Each property corresponds to a distinct Instruments category.
public enum CisumLog {
    /// App lifecycle — launch, scene transitions, bootstrap.
    public static let lifecycle: os.Logger = .init(subsystem: kSubsystem, category: "Lifecycle")
    /// Audio playback engine — AVPlayer, candidates, format selection.
    public static let playback: os.Logger = .init(subsystem: kSubsystem, category: "Playback")
    /// Stream resolution — PlaybackURLResolver, provider races.
    public static let resolver: os.Logger = .init(subsystem: kSubsystem, category: "StreamResolver")
    /// Metadata cache — VideoMetadataCache hit/miss/eviction.
    public static let cache: os.Logger = .init(subsystem: kSubsystem, category: "MetadataCache")
    /// Artwork pipeline — fetch, colour extraction, motion artwork.
    public static let artwork: os.Logger = .init(subsystem: kSubsystem, category: "Artwork")
    /// Search — query dispatch, result ranking, cache hints.
    public static let search: os.Logger = .init(subsystem: kSubsystem, category: "Search")
    /// Queue management — preloading, radio continuation, skip.
    public static let queue: os.Logger = .init(subsystem: kSubsystem, category: "Queue")
    /// Networking — HTTP requests, bandwidth, errors.
    public static let network: os.Logger = .init(subsystem: kSubsystem, category: "Network")
    /// SwiftData / persistence — reads, writes, migrations.
    public static let persistence: os.Logger = .init(subsystem: kSubsystem, category: "Persistence")
    /// Swift Concurrency — actor contention, task scheduling.
    public static let concurrency: os.Logger = .init(subsystem: kSubsystem, category: "Concurrency")
}

// MARK: - OSSignposter namespace

/// Per-category `OSSignposter` instances.
/// Calling `beginInterval` / `endInterval` emits spans visible in Instruments
/// under the matching subsystem + category combination.
public enum CisumSignpost {
    /// Lifecycle — app launch, scene transitions.
    public static let lifecycle = OSSignposter(subsystem: kSubsystem, category: "Lifecycle")
    /// Playback pipeline spans (tap→play, candidate selection, seek).
    public static let playback = OSSignposter(subsystem: kSubsystem, category: "Playback")
    /// Stream resolution race spans.
    public static let resolver = OSSignposter(subsystem: kSubsystem, category: "StreamResolver")
    /// Metadata cache I/O spans.
    public static let cache = OSSignposter(subsystem: kSubsystem, category: "MetadataCache")
    /// Artwork load spans.
    public static let artwork = OSSignposter(subsystem: kSubsystem, category: "Artwork")
    /// Search pipeline spans.
    public static let search = OSSignposter(subsystem: kSubsystem, category: "Search")
    /// Queue preload spans.
    public static let queue = OSSignposter(subsystem: kSubsystem, category: "Queue")
}

// MARK: - OSSignposter Convenience Extensions

public extension OSSignposter {
    // -------------------------------------------------------------------------
    // OSSignposter.beginInterval returns an OSSignpostIntervalState (Swift 5.9+)
    // which must be passed back to endInterval.  We expose begin/end helpers
    // that match this opaque-state API so callers don't need to manage it manually.
    // -------------------------------------------------------------------------

    /// Begins a signpost interval and returns the opaque interval state.
    /// - Parameters:
    ///   - name:    Must be a string literal (StaticString) per os_signpost contract.
    ///   - message: Optional freeform context embedded in the interval begin event.
    @discardableResult
    @inlinable
    func begin(_ name: StaticString, _ message: String = "") -> OSSignpostIntervalState {
        let spid = makeSignpostID()
        if message.isEmpty {
            return beginInterval(name, id: spid)
        } else {
            return beginInterval(name, id: spid, "\(message)")
        }
    }

    /// Ends a signpost interval previously started with `begin(_:_:)`.
    @inlinable
    func end(_ name: StaticString, state: OSSignpostIntervalState, _ message: String = "") {
        if message.isEmpty {
            endInterval(name, state)
        } else {
            endInterval(name, state, "\(message)")
        }
    }

    /// Emits a zero-duration point-of-interest event.
    @inlinable
    func event(_ name: StaticString, _ message: String = "") {
        let spid = makeSignpostID()
        if message.isEmpty {
            emitEvent(name, id: spid)
        } else {
            emitEvent(name, id: spid, "\(message)")
        }
    }

    /// Synchronously traces `operation` between a begin/end signpost pair.
    @inlinable
    func trace<T>(
        _ name: StaticString,
        _ message: String = "",
        operation: () throws -> T
    ) rethrows -> T {
        let state = begin(name, message)
        defer { end(name, state: state) }
        return try operation()
    }

    /// Asynchronously traces `operation` between a begin/end signpost pair.
    @inlinable
    func traceAsync<T>(
        _ name: StaticString,
        _ message: String = "",
        operation: () async throws -> T
    ) async rethrows -> T {
        let state = begin(name, message)
        defer { end(name, state: state) }
        return try await operation()
    }
}
