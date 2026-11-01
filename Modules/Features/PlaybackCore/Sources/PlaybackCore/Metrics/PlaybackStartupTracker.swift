//
//  PlaybackStartupTracker.swift
//  PlaybackCore
//
//  Exactly-once accounting for the first-time-advancing startup proxy.
//
//  The problem it solves: a periodic observer keeps firing for every track, so a naive
//  implementation records a "startup" for the wrong request, or many times for one request, or for
//  a request the user already skipped past. This tracker ties each measurement to a request id and
//  guarantees a single terminal outcome per request.
//

import Foundation

/// Tracks one startup measurement per playback request and reports a single outcome for each.
///
/// The metric it feeds is the **first-time-advancing proxy** — the time from play intent to the
/// first observed advancement of the item. It is *not* tap-to-first-audio; true audible output is
/// not measurable programmatically.
@MainActor
public struct PlaybackStartupTracker {
    /// A completed proxy measurement.
    public struct Measurement: Equatable, Sendable {
        public let requestID: Int
        /// Milliseconds from play intent to the first qualifying time advancement.
        public let milliseconds: Double

        public init(requestID: Int, milliseconds: Double) {
            self.requestID = requestID
            self.milliseconds = milliseconds
        }
    }

    /// The single terminal outcome of a startup attempt.
    public enum Outcome: Equatable, Sendable {
        /// The item first advanced — a successful proxy measurement.
        case firstAdvance(Measurement)
        /// The attempt failed before any advancement (resolve error, unplayable track).
        case failed(requestID: Int)
        /// The attempt was superseded by a newer request, or playback stopped.
        case cancelled(requestID: Int)
    }

    /// The result of starting a request: the intent instant, and the outcome of any request it
    /// superseded.
    public struct Begin: Sendable {
        public let intent: ContinuousClock.Instant
        public let superseded: Outcome?
    }

    private let now: @MainActor () -> ContinuousClock.Instant
    private var pending: (requestID: Int, intent: ContinuousClock.Instant)?

    /// - Parameter now: A monotonic clock source. Injectable so tests are deterministic.
    public init(now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// Whether a request is currently awaiting an outcome.
    public var hasPendingMeasurement: Bool {
        pending != nil
    }

    /// Begins a new request, superseding any still-pending one.
    @discardableResult
    public mutating func begin(requestID: Int) -> Begin {
        let intent = now()
        let superseded = pending.map { Outcome.cancelled(requestID: $0.requestID) }
        pending = (requestID, intent)
        return Begin(intent: intent, superseded: superseded)
    }

    /// Records the first time advancement for `requestID`.
    ///
    /// Returns `nil` — and records nothing — when the request is not the pending one, which is how a
    /// stale observer callback for a superseded request is ignored.
    public mutating func completeFirstAdvance(requestID: Int) -> Outcome? {
        guard let pending, pending.requestID == requestID else { return nil }
        self.pending = nil
        return .firstAdvance(Measurement(
            requestID: requestID,
            milliseconds: pending.intent.duration(to: now()).milliseconds
        ))
    }

    /// Records that `requestID` failed before any advancement.
    public mutating func fail(requestID: Int) -> Outcome? {
        guard let pending, pending.requestID == requestID else { return nil }
        self.pending = nil
        return .failed(requestID: requestID)
    }

    /// Records that `requestID` was cancelled (playback stopped, or no successor request will).
    public mutating func cancel(requestID: Int) -> Outcome? {
        guard let pending, pending.requestID == requestID else { return nil }
        self.pending = nil
        return .cancelled(requestID: requestID)
    }
}
