//
//  CrossfadeTests.swift
//  PlaybackCoreTests
//

import Models
@testable import PlaybackCore
import Testing

private func ref(_ id: String, album: String?) -> PlayableRef {
    PlayableRef(songID: id, sourceID: "test", sourceTrackID: id, title: id, artist: "Artist", album: album)
}

@Suite("Crossfade")
struct CrossfadeTests {
    @Test("tracks of one album run gaplessly; anything else takes the requested fade")
    func albumIsGapless() {
        #expect(Crossfade.seconds(requested: 6, from: ref("a", album: "After Hours"), to: ref("b", album: "After Hours")) == 0)
        #expect(Crossfade.seconds(requested: 6, from: ref("a", album: "After Hours"), to: ref("b", album: "Starboy")) == 6)
        #expect(Crossfade.seconds(requested: 6, from: ref("a", album: nil), to: ref("b", album: nil)) == 6)
        #expect(Crossfade.seconds(requested: 6, from: ref("a", album: ""), to: ref("b", album: "")) == 6)
    }

    @Test("a fade never takes more than a third of the track")
    func lengthCapped() {
        #expect(Crossfade.length(12, trackLength: 30) == 10)
        #expect(Crossfade.length(6, trackLength: 200) == 6)
    }

    @Test("equal-power gains: full to silent, constant power throughout")
    func gains() {
        let start = Crossfade.gains(at: 0), end = Crossfade.gains(at: 1)
        #expect(start.outgoing == 1 && start.incoming == 0)
        #expect(abs(end.outgoing) < 1e-6 && end.incoming == 1)
        for step in 0 ... 10 {
            let g = Crossfade.gains(at: Double(step) / 10)
            #expect(abs(g.outgoing * g.outgoing + g.incoming * g.incoming - 1) < 1e-5)
        }
    }
}
