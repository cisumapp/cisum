//
//  PlaybackQueueTests.swift
//  PlayerTests
//

import Foundation
import Models
@testable import PlaybackCore
import Testing

private func ref(_ id: String) -> PlayableRef {
    PlayableRef(
        songID: id, sourceID: "test", sourceTrackID: id,
        title: "Track \(id)", artist: "Artist"
    )
}

private let a = ref("a"), b = ref("b"), c = ref("c"), d = ref("d")

@MainActor
@Suite("Playback queue")
struct PlaybackQueueTests {
    @Test("an empty queue has no current entry and cannot skip")
    func emptyQueue() {
        let queue = PlaybackQueue()
        #expect(queue.current == nil)
        #expect(queue.isEmpty)
        #expect(!queue.canSkipForward)
        #expect(!queue.canSkipBackward)
    }

    @Test("replacing sets the queue and honours the start index")
    func replace() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c], startIndex: 1)
        #expect(queue.current == b)
        #expect(queue.count == 3)
    }

    @Test("an out-of-range start index is clamped rather than crashing")
    func clampedStartIndex() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b], startIndex: 99)
        #expect(queue.current == b)
    }

    @Test("advancing walks forward and stops at the end")
    func advanceStopsAtEnd() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b])

        #expect(queue.advance() == b)
        #expect(queue.advance() == nil) // finished
        #expect(queue.current == b) // and stays put
    }

    @Test("repeatAll wraps around")
    func repeatAllWraps() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b])
        queue.mode = .repeatAll

        #expect(queue.advance() == b)
        #expect(queue.advance() == a)
    }

    @Test("repeatOne returns the same entry")
    func repeatOne() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b])
        queue.mode = .repeatOne

        #expect(queue.advance() == a)
        #expect(queue.current == a)
    }

    /// Standard behaviour in every music player: previous restarts rather than refusing.
    @Test("retreating from the first entry stays put so the track can restart")
    func retreatAtStart() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b])
        #expect(queue.retreat() == a)
        #expect(queue.canSkipBackward)
    }

    /// The bug users notice: shuffling the whole list and then hunting for the tapped track means
    /// tapping a song sometimes plays a different one.
    @Test("shuffling on replace keeps the chosen track playing first")
    func shuffleKeepsChosenTrackFirst() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 2, shuffled: true)

        #expect(queue.current == c)
        #expect(queue.count == 4)
    }

    @Test("turning shuffle on keeps the current track playing")
    func shuffleOnKeepsCurrent() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 1)
        queue.mode = .shuffle

        #expect(queue.current == b)
        #expect(queue.count == 4)
    }

    @Test("turning shuffle off restores the original order, still on the same track")
    func shuffleOffRestoresOrder() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 1)
        queue.mode = .shuffle
        queue.mode = .off

        #expect(queue.entries == [a, b, c, d])
        #expect(queue.current == b)
    }

    @Test("removing an earlier entry keeps the same track playing")
    func removeBeforeCurrent() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c], startIndex: 2)
        queue.remove(at: 0)

        #expect(queue.current == c)
        #expect(queue.count == 2)
    }

    @Test("removing the current entry falls through to the next")
    func removeCurrent() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c], startIndex: 1)
        queue.remove(at: 1)

        #expect(queue.current == c)
    }

    @Test("removing the last remaining entry empties the queue")
    func removeOnlyEntry() {
        let queue = PlaybackQueue()
        queue.replace(with: [a])
        queue.remove(at: 0)

        #expect(queue.isEmpty)
        #expect(queue.current == nil)
    }

    @Test("insertNext places a track immediately after the current one")
    func insertNext() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, c])
        queue.insertNext(b)

        #expect(queue.entries == [a, b, c])
        #expect(queue.current == a)
    }

    @Test("playing with preserveQueue jumps to the track when it is already queued")
    func playPreservingQueue() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c])
        queue.play(c, preserveQueue: true)

        #expect(queue.current == c)
        #expect(queue.count == 3)
    }

    @Test("playing without preserveQueue replaces everything")
    func playReplacingQueue() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c])
        queue.play(d, preserveQueue: false)

        #expect(queue.entries == [d])
        #expect(queue.current == d)
    }

    @Test("the mode cycles off → shuffle → repeatAll → repeatOne → off")
    func modeCycles() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b])

        #expect(queue.mode == .off)
        queue.cycleMode(); #expect(queue.mode == .shuffle)
        queue.cycleMode(); #expect(queue.mode == .repeatAll)
        queue.cycleMode(); #expect(queue.mode == .repeatOne)
        queue.cycleMode(); #expect(queue.mode == .off)
    }

    @Test("the preview shows what comes next, without the current entry")
    func preview() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d])

        #expect(queue.preview() == [b, c, d])
        #expect(queue.preview(limit: 2) == [b, c])
    }

    /// Identity is the (source, track) pair — not the display strings, which differ between
    /// services for the same recording.
    @Test("refs compare by source and track id only")
    func refIdentity() {
        let one = PlayableRef(
            songID: "s1",
            sourceID: "tidal",
            sourceTrackID: "42",
            title: "Ivy",
            artist: "Frank Ocean"
        )
        let two = PlayableRef(
            songID: nil,
            sourceID: "tidal",
            sourceTrackID: "42",
            title: "IVY (Album Version)",
            artist: "F. Ocean"
        )
        let other = PlayableRef(
            songID: "s1",
            sourceID: "qobuz",
            sourceTrackID: "42",
            title: "Ivy",
            artist: "Frank Ocean"
        )

        #expect(one == two)
        #expect(one != other)
    }
}

@MainActor
@Suite("Radio-filled queue")
struct RadioQueueTests {
    private func song(_ id: String, _ title: String, _ artist: String, source: String = "youtube_music") -> PlayableRef {
        PlayableRef(songID: nil, sourceID: source, sourceTrackID: id, title: title, artist: artist)
    }

    @Test("turning shuffle on never puts played tracks back in front")
    func shuffleKeepsHistoryBehind() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 2)
        queue.mode = .shuffle
        #expect(queue.position == 2)
        #expect(Array(queue.entries.prefix(3)) == [a, b, c])
        #expect(queue.entries.last == d)
    }

    @Test("the same song from another service is not appended twice")
    func crossServiceDuplicateDropped() {
        let queue = PlaybackQueue()
        queue.replace(with: [song("yt1", "Yellow", "Coldplay")])
        let added = queue.appendUnique([
            song("sp1", "Yellow", "Coldplay", source: "spotify"),
            song("yt2", "Coldplay - Yellow (Official Video)", "Coldplay"),
            song("yt3", "Clocks", "Coldplay"),
            song("sp2", "Clocks", "Coldplay", source: "spotify"),
        ])
        #expect(added.map(\.sourceTrackID) == ["yt3"])
        #expect(queue.count == 2)
    }

    @Test("featured-artist spelling does not defeat de-duplication")
    func featuredArtistsIgnored() {
        let queue = PlaybackQueue()
        queue.replace(with: [song("a", "Like That", "Future, Metro Boomin")])
        #expect(queue.appendUnique([song("b", "Like That", "Future & Metro Boomin", source: "spotify")]).isEmpty)
    }

    @Test("radio tracks appended while shuffled stay after the current track")
    func appendWhileShuffled() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b], startIndex: 1)
        queue.mode = .shuffle
        queue.appendUnique([c, d])
        #expect(queue.current == b)
        #expect(Set(queue.entries.suffix(2)) == [c, d])
        queue.mode = .off
        #expect(queue.current == b)
        #expect(queue.entries == [a, b, c, d])
    }
}

@MainActor
@Suite("Queue reordering")
struct QueueMoveTests {
    @Test("moving an upcoming entry keeps the same track playing")
    func moveKeepsCurrent() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 1)
        queue.move(from: 3, to: 2)
        #expect(queue.entries == [a, b, d, c])
        #expect(queue.current == b)
        queue.move(from: 2, to: 4)
        #expect(queue.entries == [a, b, c, d])
    }

    @Test("the playing entry cannot be moved")
    func currentStaysPut() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c], startIndex: 1)
        queue.move(from: 1, to: 3)
        #expect(queue.entries == [a, b, c])
    }

    @Test("a reorder survives turning shuffle on and off")
    func reorderSurvivesShuffle() {
        let queue = PlaybackQueue()
        queue.replace(with: [a, b, c, d], startIndex: 0)
        queue.move(from: 3, to: 1)
        queue.mode = .shuffle
        queue.mode = .off
        #expect(queue.entries == [a, d, b, c])
    }
}
