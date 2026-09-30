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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 860)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
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
            }

            MacBarProgress()
                .frame(maxWidth: 190)
        }
        .frame(minWidth: 300, alignment: .leading)
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
