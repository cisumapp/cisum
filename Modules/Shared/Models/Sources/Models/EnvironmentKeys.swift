import SwiftUI

public extension EnvironmentValues {
    /// Commands for starting and controlling playback.
    ///
    /// Replaces `\.playerViewModel`, which handed every view the whole player. That meant a view
    /// wanting only to *start* playback observed all 34 members of the old interface and
    /// re-rendered roughly thirty times a second while the position ticked.
    ///
    /// `PlaybackCommands` publishes no state, so a view holding one is never invalidated by
    /// playback. Views that need to *display* state take the specific object they read —
    /// `@Environment(NowPlayingState.self)`, `@Environment(TransportState.self)`, and so on.
    ///
    /// Optional, with no dummy default. The previous `DummyPlayerViewModel` silently swallowed
    /// every call when the environment was not wired, so a missing injection looked like a player
    /// that just did not respond. `nil` makes the mistake visible.
    @Entry var playbackCommands: (any PlaybackCommands)?

    /// Sources to prefer for playback, best first.
    ///
    /// Set by the composition root from the user's plugin ordering. Views pass it to
    /// `Song.playableRef(preferring:)` so a song plays from the user's chosen service when it has
    /// a representation there, and falls back to whatever else it has when it does not.
    @Entry var preferredSourceIDs: [String] = []

    @Entry var searchViewModel: (any SearchViewModelInterface)?

    @Entry var savedLibrary: (any SavedLibraryInterface)?
}
