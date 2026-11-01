//
//  CandidateCollection.swift
//  PlaybackCore
//
//  Asking several providers at once, under a bound, and keeping the record of who answered.
//

import Foundation
import ProviderSDK

/// How long a playback request is willing to wait, and for what.
///
/// A **policy** value, not a measurement. `TARGET_ARCHITECTURE` §16 Phase 4 owns measured per-phase
/// startup budgets, and that phase is blocked on U-1 (benchmark infrastructure that does not exist
/// yet). This is the safety valve that makes cross-provider resolution bounded in the meantime:
/// it decides only how long cisum is willing to let another provider improve on the candidate it
/// already has, and the composition root can replace it without touching resolution logic.
///
/// **Two windows, because there are two different questions.** The previous shape had one: every
/// provider had to answer inside a fixed 800 ms or its contribution — and, when it was the only
/// provider, the whole request — was discarded. That window is fine as a bound on *improving* an
/// answer cisum already holds, and wrong as a bound on obtaining the first one: a provider that
/// answers in 900 ms is not broken, it is a provider, and the app reported the track as unplayable.
public struct ResolutionBudget: Sendable, Equatable {
    /// How long the remaining providers get to beat a candidate cisum already has.
    ///
    /// Measured **from the moment the first usable candidate arrives**, not from the start of the
    /// request. A provider that has not answered by the end of this window does not participate in
    /// ranking: audio is already on its way, and cisum does not hold it up to look for something
    /// nominally better. This is the only window that can drop a contribution.
    public var improvementWindow: Duration

    /// The longest a request may wait for its **first** usable candidate.
    ///
    /// A backstop for a provider that has hung, not a latency budget — a provider that answers
    /// inside this window is used, however long it took. Every provider bounds its own work
    /// (URLSession timeouts, and the YouTube ladder's own extraction deadline), so this should
    /// never be what ends a request; it exists so that a provider which never returns at all cannot
    /// leave the user waiting behind a spinner indefinitely.
    public var firstCandidateTimeout: Duration

    public init(
        improvementWindow: Duration = .milliseconds(800),
        firstCandidateTimeout: Duration = .seconds(15)
    ) {
        self.improvementWindow = improvementWindow
        self.firstCandidateTimeout = firstCandidateTimeout
    }

    /// The default. The improvement window is deliberately short: it is added to the *other*
    /// providers' response time, not to the selected provider's.
    public static let `default` = ResolutionBudget()
}

/// What one provider contributed, and how it was resolved.
public struct SourceStreams: Sendable, Equatable {
    /// The track id these streams were resolved for. This is the id the binding is persisted
    /// against, and after a search it is the *matched* id rather than the one that was asked for.
    public let trackID: String

    /// Every stream the provider offered, in the provider's own order.
    public let streams: [SourceStream]

    /// The identity evidence that applies to them.
    public let identity: CandidateIdentity

    public init(trackID: String, streams: [SourceStream], identity: CandidateIdentity) {
        self.trackID = trackID
        self.streams = streams
        self.identity = identity
    }
}

/// The terminal state of one provider's attempt for one request.
public enum SourceResolveResult: Sendable, Equatable {
    /// The provider answered. An empty `streams` list is a real answer meaning "nothing playable".
    case answered(SourceStreams)
    /// The provider has no representation of this track at all — a search with no acceptable match,
    /// or no stored id to resolve. A normal outcome, and one worth distinguishing from a failure.
    case nothing
    /// The provider did not answer within the budget. Abandoned for this request.
    case timedOut
    /// The provider threw. The reason is the error's **type name**, never its message.
    ///
    /// A provider error message is free-form text that routinely embeds the URL it failed on, and
    /// that URL is a credential until it expires. The type name is enough to tell a network failure
    /// from a decoding failure from a refusal, which is what diagnostics actually need, and it cannot
    /// carry a signed URL or a token into a log.
    case failed(reason: String)
}

/// One provider's task for a request.
///
/// The work is a closure rather than a protocol call so the same collection covers both ways a
/// provider can contribute: a direct resolve by an id cisum already stored (no search), and a
/// search-then-resolve when no stored id exists. Deciding *which* is the resolver's job; running
/// them concurrently under a bound is this type's.
public struct SourceResolveJob: Sendable {
    /// The provider's id, for diagnostics and for source trust.
    public let sourceID: String

    /// The caller's preference order. Lower is more preferred, and it is the final tie-break in
    /// ranking — never a quality signal.
    public let order: Int

    /// Resolves this provider's contribution, or `nil` when it has nothing for this track.
    public let work: @Sendable () async throws -> SourceStreams?

    public init(sourceID: String, order: Int, work: @escaping @Sendable () async throws -> SourceStreams?) {
        self.sourceID = sourceID
        self.order = order
        self.work = work
    }
}

/// What happened for one provider, kept for diagnostics and for classifying the failure.
public struct SourceResolveReport: Sendable, Equatable {
    public let sourceID: String
    public let order: Int
    public let result: SourceResolveResult

    public init(sourceID: String, order: Int, result: SourceResolveResult) {
        self.sourceID = sourceID
        self.order = order
        self.result = result
    }

    /// The contribution, when the provider answered.
    public var streams: SourceStreams? {
        if case let .answered(streams) = result {
            return streams
        }
        return nil
    }

    /// Whether this provider actually supplied something playable.
    ///
    /// An empty stream list is a genuine answer — "this provider has nothing" — and a different
    /// thing from a failure, but it is not a candidate: it must not close the window that exists to
    /// obtain the *first* one.
    public var hasUsableStreams: Bool {
        guard case let .answered(streams) = result else { return false }
        return !streams.streams.isEmpty
    }
}

/// Runs provider jobs concurrently and reports every outcome.
///
/// **Concurrent on purpose.** The previous resolver walked the provider list one at a time and
/// returned on the first provider that produced a usable stream, so which provider won was decided
/// by registry order — a provider later in the list could never contribute, however much better its
/// stream was. Resolving in parallel is also the cheapest correct answer: the wall-clock cost is the
/// slowest provider rather than the sum.
///
/// **Collecting is not the same as waiting.** Every job runs to completion in parallel; what the
/// budget bounds is how long the *ranking* is willing to wait for more candidates. A provider that
/// has not answered when the improvement window closes is reported `.timedOut` and its task is
/// cancelled — it does not stop the request, and it does not stop audio from starting on the
/// candidate that did answer. Crucially, a provider that has not answered yet is **not** abandoned
/// while there is nothing to play: the first usable candidate is what ends the wait, so a slow
/// provider can still be the one that saves the request. See `ResolutionBudget`.
///
/// Structured throughout: the work runs as children of one group, so returning cancels whatever is
/// still running and nothing outlives the request. A provider that ignores cancellation can still
/// delay the *return* past its window — the window decides what is allowed to participate in
/// ranking, not how long a misbehaving provider can occupy a task.
public enum CandidateCollection {
    /// Runs every job, bounded by `budget`, and returns one report per job.
    ///
    /// - Returns: One report per job, in the caller's preference order rather than completion order,
    ///   so diagnostics are deterministic regardless of which provider answered first. A job that had
    ///   not answered when the budget ran out is `.timedOut`.
    public static func collect(
        _ jobs: [SourceResolveJob],
        within budget: ResolutionBudget
    ) async -> [SourceResolveReport] {
        guard !jobs.isEmpty else { return [] }

        // The rendezvous between the jobs and this collector. A plain task group cannot express the
        // rule ("stop early, but only once there is something to play") because a result that
        // arrives is not the same event as a group that has finished, and cancelling the group to
        // stop waiting would throw away the slower providers' candidates — which is exactly the
        // cross-provider ranking this type exists for.
        let relay = OutcomeRelay()

        var reports: [SourceResolveReport] = []
        reports.reserveCapacity(jobs.count)

        await withTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    let result = await result(of: job)
                    await relay.push(SourceResolveReport(sourceID: job.sourceID, order: job.order, result: result))
                }
            }

            // Collecting ends when every job has reported, when a usable candidate has been in hand
            // for the improvement window, or — with nothing to play — at the first-candidate
            // backstop. The loop condition is the first: the other two end the *wait* inside.
            var collected: [SourceResolveReport] = []
            while collected.count < jobs.count {
                let candidate = await relay.nextReport(
                    after: budget,
                    usableSoFar: collected.contains(where: \.hasUsableStreams)
                )
                guard let next = candidate else { break }
                collected.append(next)
            }
            reports = collected

            // Whatever is still running is abandoned rather than left to occupy a task; the group's
            // children are cancelled on return, and the provider's own cancellation handling decides
            // how fast that takes effect.
            await relay.close()
            group.cancelAll()
        }

        // A job that never reported was abandoned, and that is what `.timedOut` means. Anything it
        // returns after this point cannot reach the caller: the relay is closed and the task is
        // cancelled.
        let reported = Set(reports.map(\.order))
        for job in jobs where !reported.contains(job.order) {
            reports.append(SourceResolveReport(sourceID: job.sourceID, order: job.order, result: .timedOut))
        }

        return reports.sorted { $0.order < $1.order }
    }

    /// Maps one provider's work to its terminal state. No deadline here: the deadline belongs to the
    /// collection, not to the provider, so a slow provider still delivers its candidates if cisum is
    /// still waiting for any.
    private static func result(of job: SourceResolveJob) async -> SourceResolveResult {
        do {
            guard let streams = try await job.work() else { return .nothing }
            return .answered(streams)
        } catch {
            return .failed(reason: String(describing: type(of: error)))
        }
    }
}

/// Single-consumer rendezvous for provider outcomes: jobs push, the collector pulls.
///
/// An `actor` because the push and the pull happen on different tasks, and the invariant that
/// matters is that a report is delivered exactly once — to the collector if it is waiting, into the
/// queue if it is not.
private actor OutcomeRelay {
    private var queue: [SourceResolveReport] = []
    private var waiter: CheckedContinuation<SourceResolveReport?, Never>?
    private var closed = false

    /// Hands a report to a waiting collector, or queues it for the next pull.
    func push(_ report: SourceResolveReport) {
        guard let pending = waiter else {
            queue.append(report)
            return
        }
        waiter = nil
        pending.resume(returning: report)
    }

    /// Wakes a pending pull with `nil` so the collector can stop. Idempotent, and safe to call while
    /// a job is still running: a report that arrives afterwards is queued and never delivered.
    func close() {
        closed = true
        guard let pending = waiter else { return }
        waiter = nil
        pending.resume(returning: nil)
    }

    /// The next report, waiting at most for the window `budget` allows *given what is already in
    /// hand*. `nil` means "stop waiting": either every job has reported, or the window closed.
    ///
    /// This is where the two windows are applied, and applying them here rather than per provider is
    /// the correction that matters. With a candidate already collected, the remaining providers get
    /// `improvementWindow` — long enough to add a better stream to the ranking, short enough not to
    /// delay audio that could already be playing. With nothing collected, they get
    /// `firstCandidateTimeout`, because there is no audio to protect and abandoning the only provider
    /// is precisely the failure that made a working provider look broken.
    func nextReport(after budget: ResolutionBudget, usableSoFar: Bool) async -> SourceResolveReport? {
        if !queue.isEmpty {
            return queue.removeFirst()
        }
        if closed {
            return nil
        }

        let window = usableSoFar ? budget.improvementWindow : budget.firstCandidateTimeout
        let deadline = ContinuousClock.now + window

        // The timer is an unstructured task on purpose: it must outlive the suspension below without
        // being a child of it, so that a push which wins the race cancels nothing but the wake-up.
        // A stale expiry can never hurt: it only resumes the waiter whose id it was minted for.
        waiterID &+= 1
        let id = waiterID
        let expiry = Task { [weak self] in
            let remaining = ContinuousClock.now.duration(to: deadline)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            await self?.expire(waiterID: id)
        }
        defer { expiry.cancel() }

        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    private var waiterID = 0

    /// Resumes a pull that is still the current one. The id check is what makes a late expiry
    /// harmless: by the time it fires, either the waiter is gone (a report arrived) or it is a newer
    /// wait, which this must not cut short.
    private func expire(waiterID id: Int) {
        guard waiterID == id, let pending = waiter else { return }
        waiter = nil
        pending.resume(returning: nil)
    }
}
