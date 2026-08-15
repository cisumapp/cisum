//
//  NowPlayingMode.swift
//  Player
//

import Foundation

/// What the expanded player is showing in its main area.
///
/// Replaces the previous `isLyricsVisible` + `isQueueVisible` pair. Two booleans could represent
/// four states for three real ones, so the impossible combination had to be prevented by hand at
/// every toggle:
///
/// ```swift
/// if pvm.isLyricsVisible { pvm.isLyricsVisible = false }
/// else { pvm.isQueueVisible = false; pvm.isLyricsVisible = true }
/// ```
///
/// and when both ended up true anyway, the view's `if/else if` ordering silently picked queue.
/// One case cannot be in two states, so the toggles become assignments and the view becomes a
/// `switch` the compiler checks for exhaustiveness.
public enum NowPlayingMode: String, Sendable, CaseIterable {
    /// The theme's own artwork treatment fills the stage. In the default theme that is the vinyl
    /// showing through from behind, which is why the stage draws `Color.clear` rather than an image.
    case artwork
    case lyrics
    case queue
}
