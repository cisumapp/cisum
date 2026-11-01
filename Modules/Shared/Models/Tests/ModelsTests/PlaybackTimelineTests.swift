@testable import Models
import XCTest

/// The canonical-vs-observed duration rule.
///
/// The two numbers answer different questions — what the catalogue promised and what the loaded file
/// actually is — and the timeline is measured against the second while it exists. What must never
/// happen is inventing either: an unknown, zero, negative, NaN or infinite value is not a length, and
/// the difference between "no known length" and "length 0" is the difference between an empty
/// scrubber and a track that looks finished.
final class PlaybackTimelineTests: XCTestCase {
    func testOnlyFinitePositiveValuesAreUsable() {
        XCTAssertEqual(PlaybackTimeline.usable(249), 249)
        XCTAssertEqual(PlaybackTimeline.usable(0.5), 0.5)
        XCTAssertNil(PlaybackTimeline.usable(nil))
        XCTAssertNil(PlaybackTimeline.usable(0))
        XCTAssertNil(PlaybackTimeline.usable(-5))
        XCTAssertNil(PlaybackTimeline.usable(.nan))
        XCTAssertNil(PlaybackTimeline.usable(.infinity))
    }

    func testObservedItemDurationIsTheTimeline() {
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 249, observed: 251), 251)
    }

    /// AVFoundation estimated YouTube's fragmented-MP4 "Thin Ice" (2:27) at 4:53; the stream's own
    /// `dur` must win over that estimate.
    func testReportedStreamDurationOutranksTheObservedEstimate() {
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 0, observed: 293, reported: 147), 147)
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 150, observed: 293, reported: nil), 293)
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 150, observed: nil, reported: 0), 150)
    }

    func testCanonicalIsUsedUntilTheItemReportsOne() {
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 249, observed: nil), 249)
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 249, observed: 0), 249)
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 249, observed: .nan), 249)
        XCTAssertEqual(PlaybackTimeline.duration(canonical: 249, observed: -1), 249)
    }

    func testUnknownOnBothSidesIsUnknownRatherThanZero() {
        XCTAssertNil(PlaybackTimeline.duration(canonical: 0, observed: nil))
        XCTAssertNil(PlaybackTimeline.duration(canonical: -1, observed: .infinity))
        XCTAssertNil(PlaybackTimeline.duration(canonical: .nan, observed: .nan))
    }

    @MainActor
    func testStateKeepsCanonicalMetadataWhenTheItemReportsItsOwnLength() {
        let state = NowPlayingState()
        state.duration = 249
        XCTAssertEqual(state.timelineDuration, 249)

        state.observedItemDuration = 251
        XCTAssertEqual(state.timelineDuration, 251, "the timeline is what is actually playing")
        XCTAssertEqual(state.duration, 249, "canonical metadata is not overwritten by the item")

        state.observedItemDuration = nil
        XCTAssertEqual(state.timelineDuration, 249)

        state.duration = 0
        XCTAssertNil(state.timelineDuration, "unknown is not zero")
    }

    @MainActor
    func testClearingItemDurationDoesNotChangeCanonicalDuration() {
        let state = NowPlayingState()
        state.duration = 200
        state.observedItemDuration = 198
        state.observedItemDuration = nil
        XCTAssertEqual(state.timelineDuration, 200)
    }
}
