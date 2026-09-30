//
//  PlayerModule.swift
//  Player
//
//  The package's front door.
//

import Aesthetics
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
        #if os(iOS)
        DynamicPlayerIsland(isPlayerExpanded: isExpanded, namespace: namespace)
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
        #elseif os(macOS)
        // The macOS island reads `PlayerViewModel` and `ProgressState` from the
        // environment just like the iOS one, so it needs the same two injections —
        // it has no namespace-driven transitions, hence no `namespace` here.
        DynamicPlayerIsland()
            .environment(viewModel)
            .environment(viewModel.progress)
        #endif
    }

    /// The full-screen player.
    public func expandablePlayer(
        show: Binding<Bool>,
        isExpanded: Binding<Bool>,
        collapsedFrame: CGRect
    ) -> some View {
        #if os(iOS)
        ExpandablePlayer(show: show, isPlayerExpanded: isExpanded, collapsedFrame: collapsedFrame)
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
        #elseif os(macOS)
        EmptyView()
        #endif
    }

    /// The full player for the iOS 26 zoom cover.
    ///
    /// Distinct from `expandablePlayer` because that one carries the hand-rolled expansion — pan
    /// gesture, window stacking, collapsed geometry — which the system provides on the cover path.
    public func zoomedPlayer() -> some View {
        #if os(iOS)
        ZoomedPlayerView()
            .environment(viewModel)
            .environment(viewModel.progress)
            .environment(PlayerThemeSettings.shared)
        #elseif os(macOS)
        EmptyView()
        #endif
    }

    /// The persistent macOS transport bar. Handed out here for the same reason as the views
    /// above: constructing `PlayerBar()` directly would skip the environment injection and
    /// crash on the first missing `@Environment`.
    public func playerBar() -> some View {
        #if os(iOS)
        EmptyView()
        #elseif os(macOS)
        PlayerBar()
            .environment(viewModel)
            .environment(viewModel.progress)
        #endif
    }

    /// The rotating record behind everything on macOS. Owned by the player module so the
    /// backdrop can spin with the transport rather than needing its own copy of that state.
    public func vinylBackdrop() -> some View {
        #if os(iOS)
        EmptyView()
        #elseif os(macOS)
        VinylBackdrop(
            isPlaying: viewModel.isPlaying,
            accentColor: viewModel.nowPlaying.accentColor
        )
        .environment(viewModel)
        #endif
    }

    // MARK: - Lifecycle

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        viewModel.handleScenePhaseChange(phase)
    }
}
