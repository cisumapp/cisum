//
//  PlayerBar+macOS.swift
//  Player
//
//  The persistent floating transport that sits above the content on macOS. Unlike the
//  island it replaces, this is a horizontal bar with the full transport row, and it is
//  handed out by `PlayerModule` so `PlayerViewModel` and `ProgressState` are always injected.
//

#if os(macOS)
import Aesthetics
import Models
import SwiftUI

public struct PlayerBar: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    public init() {}

    public var body: some View {
        HStack(spacing: 18) {
            nowPlaying
            transport
            secondary
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: Self.maxWidth)
        .background { surface }
        // Restrained: the bar floats over the band, so a heavy shadow reads as a separate slab
        // sitting on top rather than as part of the same surface.
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    /// Widest the bar grows.
    ///
    /// Proportional to the window rather than fixed, so it keeps the reference's relationship
    /// to the canvas — a little over half the content column — instead of stretching to fill
    /// it on a large display or crowding it on a small one.
    private static var maxWidth: CGFloat {
        660
    }

    private static let cornerRadius: CGFloat = 12

    /// The bar's own surface.
    ///
    /// `glassEffect` on its own resolves to a mid-grey in a dark window, which is too light
    /// for a bar that has to sit over artwork; the canvas colour laid over it brings it back to
    /// the same key as the sidebar. The hairline is what separates the bar from the band behind
    /// it once the scrim has flattened the glass's own highlight.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return Group {
            if #available(macOS 26.0, *) {
                shape.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            shape.fill(Color.cisumBg.opacity(0.4))
        }
        .overlay {
            shape.strokeBorder(Color.cisumChromeSubtle, lineWidth: 1)
        }
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(playerViewModel.currentTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(playerViewModel.currentArtist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Which source is actually serving this, and what is known about the stream.
                // Hover shows the full detail; the same rows are in Settings → Diagnostics.
                ActiveStreamLabel()
            }

            MacBarProgress()
                .frame(maxWidth: 170)
        }
        .frame(minWidth: 250, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = playerViewModel.currentImageURL {
            ArtworkImage(url: url, size: 40)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cisumChromeStrong)
                .frame(width: 40, height: 40)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 14) {
            transportButton(
                "shuffle",
                help: "Playback mode",
                isActive: playerViewModel.playbackMode != .off
            ) {
                playerViewModel.cyclePlaybackMode()
            }

            transportButton("backward.fill", help: "Previous") {
                playerViewModel.skipToPrevious()
            }
            .disabled(!playerViewModel.canSkipBackward)

            Button {
                playerViewModel.togglePlayPause()
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(playerViewModel.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(playerViewModel.isPlaying ? "Pause" : "Play")

            transportButton("forward.fill", help: "Next") {
                playerViewModel.skipToNext()
            }
            .disabled(!playerViewModel.canSkipForward)

            transportButton(
                modeIcon,
                help: modeLabel,
                isActive: playerViewModeActive
            ) {
                playerViewModel.cyclePlaybackMode()
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? playerViewModel.currentAccentColor : .secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Secondary

    private var secondary: some View {
        HStack(spacing: 10) {
            transportButton("quote.bubble", help: "Lyrics") {}
            transportButton("list.bullet", help: "Queue") {}
            transportButton("speaker.wave.2.fill", help: "Volume") {}
        }
    }

    // MARK: - Playback mode

    private var modeIcon: String {
        switch playerViewModel.playbackMode {
        case .off: "repeat"
        case .shuffle: "shuffle"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        }
    }

    private var modeLabel: String {
        switch playerViewModel.playbackMode {
        case .off: "Repeat off"
        case .shuffle: "Shuffle"
        case .repeatAll: "Repeat all"
        case .repeatOne: "Repeat one"
        }
    }

    private var playerViewModeActive: Bool {
        playerViewModel.playbackMode != .off
    }
}

/// The scrubber reads `currentTime` ~30×/s, so it is isolated here: only this small view
/// re-renders at that rate instead of the whole bar around it.
/// The current track's artwork, blurred and darkened into the record band behind the transport.
///
/// It fills the band and is blurred far past recognition on purpose: the point is the *colour*
/// the artwork throws into the canvas, not the artwork itself. A sharp image up there would
/// compete with the transport and with whatever content is below it, and the band is only
/// about a fifth of the window tall.
public struct PlayerArtworkBackdrop: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    public init() {}

    public var body: some View {
        Group {
            if let url = playerViewModel.currentImageURL {
                ArtworkImage(url: url, size: Self.fetchSize)
                    // Over-scaled so the blur's soft edge never pulls in transparent pixels at
                    // the band's boundary.
                    .scaleEffect(1.25)
                    .blur(radius: Self.blurRadius)
                    // The artwork is only ever a tint here, so it is pushed well below the
                    // brightness it has on a cover.
                    .overlay { Color.black.opacity(Self.dim) }
                    .saturation(Self.saturation)
            }
        }
        // Sized by the caller, which is the only place that knows the record band's bounds.
        //
        // `ArtworkImage` finishes in `.scaledToFill()` with no frame of its own, so left
        // unsized this layer reports the decoded image's natural size into the band's
        // `ZStack`, which grows to match and pushes the transport out of the clipped band.
        // A flexible `.frame(maxWidth:maxHeight: .infinity)` here does *not* fix that — an
        // infinity frame still falls back to the child's ideal size when the proposal is
        // unspecified during the stack's own measurement. It needs a concrete size, which only
        // the band can supply, so the band applies it.
        .clipped()
        .allowsHitTesting(false)
    }

    /// Requested size for the blur's source. Blur radius works in points, so a much larger
    /// decode is what keeps the result smooth rather than blotchy at this scale.
    private static let fetchSize: CGFloat = 900

    private static let blurRadius: CGFloat = 60
    private static let dim: Double = 0.45
    private static let saturation: Double = 1.15
}

private struct MacBarProgress: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(ProgressState.self) private var progress

    var body: some View {
        VStack(spacing: 2) {
            MusicProgressScrubber(
                mediaID: playerViewModel.currentVideoId,
                currentTime: progress.currentTime,
                duration: playerViewModel.duration,
                onSeek: { playerViewModel.seek(to: $0) }
            )
            HStack {
                Text(Self.time(progress.currentTime))
                Spacer()
                Text(Self.time(playerViewModel.duration))
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
#endif
