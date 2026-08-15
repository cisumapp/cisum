//
//  PlayerModule.swift
//  Player
//
//  The package's front door.
//

import Models
import SwiftUI

/// What `PlayerModule` needs to exist.
@MainActor
public struct PlayerDependencies {
    public let viewModel: PlayerViewModel

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }
}

/// The surface other feature modules call.
///
/// Views are handed out through methods rather than as types so callers never construct a player
/// view directly, and so the environment injection below stays in one place. A caller that built
/// `ExpandablePlayer()` itself would get a crash at runtime on the first missing
/// `@Environment` — which is exactly the failure mode this avoids.
@MainActor
public final class PlayerModule {
    private let viewModel: PlayerViewModel

    public init(dependencies: PlayerDependencies) {
        self.viewModel = dependencies.viewModel
    }

    // MARK: - Properties other modules read

    /// Accent colour derived from the current artwork, for tinting surrounding chrome.
    public var accentColor: Color {
        viewModel.nowPlaying.accentColor
    }

    /// The playing track's source-specific id, or `nil` when stopped.
    ///
    /// Named for history — callers used it to correlate with YouTube. It is now whatever the
    /// active source calls the track, and is only meaningful alongside `currentSourceID`.
    public var currentVideoId: String? {
        viewModel.nowPlaying.ref?.sourceTrackID
    }

    /// Which source is playing.
    public var currentSourceID: String? {
        viewModel.nowPlaying.ref?.sourceID
    }

    /// Commands, for callers that start playback.
    public var commands: any PlaybackCommands {
        viewModel
    }

    // MARK: - Views

    // Both hand out the real views and inject what they read. `viewModel` covers the 25 members
    // the UI binds to; `progress` is injected alongside so views that display a moving clock can
    // observe it directly rather than through the view model.

    /// The collapsed player strip.
    public func miniPlayer(isExpanded: Binding<Bool>, namespace: Namespace.ID) -> some View {
        DynamicPlayerIsland(isPlayerExpanded: isExpanded, namespace: namespace)
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
    }

    /// The full-screen player.
    public func expandablePlayer(
        show: Binding<Bool>,
        isExpanded: Binding<Bool>,
        collapsedFrame: CGRect
    ) -> some View {
        ExpandablePlayer(show: show, isPlayerExpanded: isExpanded, collapsedFrame: collapsedFrame)
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
    }

    /// The full player for the iOS 26 zoom cover.
    ///
    /// Distinct from `expandablePlayer` because that one carries the hand-rolled expansion — pan
    /// gesture, window stacking, collapsed geometry — which the system provides on the cover path.
    public func zoomedPlayer() -> some View {
        ZoomedPlayerView()
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
    }

    // MARK: - Lifecycle

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        viewModel.handleScenePhaseChange(phase)
    }
}
