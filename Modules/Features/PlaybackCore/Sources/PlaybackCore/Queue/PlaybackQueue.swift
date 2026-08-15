//
//  PlaybackQueue.swift
//  Player
//
//  Queue mechanics, and nothing else.
//

import Foundation
import Models

/// The playback queue.
///
/// Based on the `Controllers/QueueManager.swift` from the previous implementation, which was a
/// clean, complete abstraction that was **never instantiated** — queue state lived directly on the
/// 1,794-line view model instead. This time the view model delegates here.
///
/// Scope is deliberately narrow: ordering, position, shuffle, repeat. What used to be
/// `PlayerViewModel+Queue.swift` was 470 lines of *radio seeding* (`seedRadioQueue`,
/// `radioSeedQuery`, `bestRadioSeedSong`, `fetchRadioContinuation`) wearing a queue's name. That
/// is a Radio feature concern — deciding what to play next is not the same as holding a list.
@MainActor
@Observable
public final class PlaybackQueue {
    /// The queue in play order. Shuffled order when shuffle is on.
    public private(set) var entries: [PlayableRef] = []

    /// Index of the current entry, or `nil` when the queue is empty.
    public private(set) var position: Int?

    /// The pre-shuffle order, so turning shuffle off restores it rather than re-sorting.
    private var unshuffled: [PlayableRef] = []

    public var mode: PlaybackMode = .off {
        didSet { modeChanged(from: oldValue) }
    }

    public init() {}

    // MARK: - Reading

    public var current: PlayableRef? {
        guard let position, entries.indices.contains(position) else { return nil }
        return entries[position]
    }

    public var count: Int {
        entries.count
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// What plays after the current entry, accounting for repeat mode.
    public var upcoming: PlayableRef? {
        guard let position else { return nil }
        if mode == .repeatOne {
            return entries[position]
        }
        let next = position + 1
        if entries.indices.contains(next) {
            return entries[next]
        }
        return mode == .repeatAll ? entries.first : nil
    }

    /// The next few entries, for the queue preview UI.
    public func preview(limit: Int = 20) -> [PlayableRef] {
        guard let position else { return [] }
        let start = min(position + 1, entries.count)
        return Array(entries[start...].prefix(limit))
    }

    public var canSkipForward: Bool {
        guard let position else { return false }
        return mode != .off || position + 1 < entries.count
    }

    /// Always true when something is playing.
    ///
    /// Previous restarts the current track when it is the first entry, which is the behaviour
    /// every music player has and users expect.
    public var canSkipBackward: Bool {
        position != nil
    }

    // MARK: - Mutating

    public func replace(with refs: [PlayableRef], startIndex: Int = 0, shuffled: Bool = false) {
        unshuffled = refs
        if shuffled, !refs.isEmpty {
            // The chosen track leads; the rest are shuffled behind it. Shuffling the whole list
            // and then hunting for the tapped track is the bug users notice.
            let start = refs.indices.contains(startIndex) ? startIndex : 0
            let chosen = refs[start]
            var rest = refs
            rest.remove(at: start)
            entries = [chosen] + rest.shuffled()
            position = 0
            mode = .shuffle
        } else {
            entries = refs
            position = refs.isEmpty ? nil : min(max(0, startIndex), refs.count - 1)
        }
    }

    /// Plays one track, optionally keeping the existing queue around it.
    public func play(_ ref: PlayableRef, preserveQueue: Bool) {
        if preserveQueue, let existing = entries.firstIndex(of: ref) {
            position = existing
            return
        }
        if preserveQueue, position != nil {
            // Insert immediately after the current entry rather than discarding the queue.
            let insertAt = (position ?? -1) + 1
            entries.insert(ref, at: min(insertAt, entries.count))
            unshuffled.append(ref)
            position = insertAt
            return
        }
        replace(with: [ref])
    }

    public func insertNext(_ ref: PlayableRef) {
        guard let position else {
            replace(with: [ref])
            return
        }
        entries.insert(ref, at: min(position + 1, entries.count))
        unshuffled.append(ref)
    }

    public func append(_ refs: [PlayableRef]) {
        entries.append(contentsOf: refs)
        unshuffled.append(contentsOf: refs)
        if position == nil, !entries.isEmpty {
            position = 0
        }
    }

    /// Advances. Returns the new entry, or `nil` when the queue has finished.
    @discardableResult
    public func advance() -> PlayableRef? {
        guard let position else { return nil }

        if mode == .repeatOne {
            return entries[position]
        }

        let next = position + 1
        if entries.indices.contains(next) {
            self.position = next
        } else if mode == .repeatAll, !entries.isEmpty {
            self.position = 0
        } else {
            return nil
        }
        return current
    }

    /// Steps back. Returns the new entry.
    @discardableResult
    public func retreat() -> PlayableRef? {
        guard let position else { return nil }
        let previous = position - 1
        if entries.indices.contains(previous) {
            self.position = previous
        } else if mode == .repeatAll, !entries.isEmpty {
            self.position = entries.count - 1
        }
        // Otherwise stay put — the caller seeks to zero, restarting the track.
        return current
    }

    public func jump(to index: Int) {
        guard entries.indices.contains(index) else { return }
        position = index
    }

    /// Removes an entry, keeping `position` pointing at the same track.
    public func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let removed = entries.remove(at: index)
        unshuffled.removeAll { $0 == removed }

        guard let position else { return }
        if index < position {
            self.position = position - 1
        } else if index == position {
            self.position = entries.isEmpty ? nil : min(position, entries.count - 1)
        }
    }

    public func clear() {
        entries = []
        unshuffled = []
        position = nil
    }

    // MARK: - Shuffle

    /// Cycles off → shuffle → repeatAll → repeatOne → off.
    public func cycleMode() {
        let order: [PlaybackMode] = [.off, .shuffle, .repeatAll, .repeatOne]
        let index = order.firstIndex(of: mode) ?? 0
        mode = order[(index + 1) % order.count]
    }

    private func modeChanged(from old: PlaybackMode) {
        guard old != mode else { return }

        if mode == .shuffle, old != .shuffle {
            guard let position, entries.indices.contains(position) else { return }
            let currentEntry = entries[position]
            unshuffled = entries
            var rest = entries
            rest.remove(at: position)
            entries = [currentEntry] + rest.shuffled()
            self.position = 0
        } else if old == .shuffle, mode != .shuffle {
            // Restore the original order, keeping the same track playing.
            let currentEntry = current
            entries = unshuffled
            position = currentEntry.flatMap { entries.firstIndex(of: $0) } ?? position
        }
    }
}
