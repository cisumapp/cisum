//
//  Crossfade.swift
//  PlaybackCore
//
//  How one track hands over to the next.
//

import Foundation
import Models

/// The rules for a track-to-track handover, kept apart from `PlaybackEngine` so they are testable
/// without a running player.
public enum Crossfade {
    /// How long `from` should fade into `to`, given the length the user asked for.
    ///
    /// Zero — a gapless cut — between two tracks of the same album, as Apple Music does: albums are
    /// sequenced to run into each other (live sets, DJ mixes, concept records), and a fade over a
    /// segue sounds like a mistake.
    public static func seconds(requested: Double, from: PlayableRef, to: PlayableRef) -> Double {
        if let album = from.album, !album.isEmpty, album == to.album {
            return 0
        }
        return max(requested, 0)
    }

    /// The fade actually used for a track of `trackLength` seconds: at most a third of the track,
    /// so a short interlude is never mostly fade.
    static func length(_ requested: Double, trackLength: Double) -> Double {
        min(requested, trackLength / 3)
    }

    /// Volumes of the outgoing and incoming tracks at `progress` (0…1) through the fade.
    ///
    /// Equal power rather than linear: two uncorrelated songs at half volume each sum to about
    /// -3 dB, the audible dip in the middle of a linear fade.
    static func gains(at progress: Double) -> (outgoing: Float, incoming: Float) {
        let t = min(max(progress, 0), 1) * .pi / 2
        return (Float(cos(t)), Float(sin(t)))
    }
}
