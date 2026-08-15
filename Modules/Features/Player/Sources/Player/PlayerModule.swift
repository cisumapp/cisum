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

    /// The collapsed player strip.
    public func miniPlayer(isExpanded _: Binding<Bool>, namespace _: Namespace.ID) -> some View {
        DynamicPlayerIsland(commands: viewModel)
            .environment(viewModel.nowPlaying)
            .environment(viewModel.transport)
    }

    /// The full-screen player.
    public func expandablePlayer(
        show _: Binding<Bool>,
        isExpanded _: Binding<Bool>,
        collapsedFrame _: CGRect
    ) -> some View {
        ExpandablePlayer(commands: viewModel)
            .environment(viewModel.nowPlaying)
            .environment(viewModel.transport)
            .environment(viewModel.progress)
            .environment(viewModel.lyrics)
    }

    // MARK: - Lifecycle

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        viewModel.handleScenePhaseChange(phase)
    }
}
