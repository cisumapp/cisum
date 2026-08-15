//
//  PlayerViews.swift
//  Player
//
//  Mini and expanded player. Structure and data flow are final; visual design is not.
//

import Models
import SwiftUI

// Every view here takes the ONE state object it reads. That is the whole point of the
// frequency-based split in PlayerState.swift, and it only pays off if the views honour it:
// a view that grabs the view model and reads four objects through it is invalidated by all four.
//
// In particular `PlayerScrubber` is the only thing in the package that touches `ProgressState`.
// If a second view starts reading it, the 30 Hz fan-out is back.

// MARK: - Mini player

/// The collapsed player strip.
public struct DynamicPlayerIsland: View {
    @Environment(NowPlayingState.self) private var nowPlaying
    @Environment(TransportState.self) private var transport
    @Environment(PlayerPresentationController.self) private var presentation

    private let commands: (any PlaybackCommands)?

    public init(commands: (any PlaybackCommands)? = nil) {
        self.commands = commands
    }

    public var body: some View {
        HStack(spacing: 12) {
            PlayerArtwork(size: 40, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(nowPlaying.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TogglePlayPauseButton(commands: commands)
            SkipForwardButton(commands: commands)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { presentation.expand() }
        .opacity(nowPlaying.isEmpty ? 0 : 1)
        .allowsHitTesting(!nowPlaying.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nowPlaying.isEmpty ? "" : "\(nowPlaying.title) by \(nowPlaying.artist)")
        // A no-argument init is required on macOS, where RootView constructs this directly.
        .animation(.snappy, value: transport.isPlaying)
    }
}

// MARK: - Expanded player

/// The full-screen player.
public struct ExpandablePlayer: View {
    @Environment(NowPlayingState.self) private var nowPlaying
    @Environment(PlayerPresentationController.self) private var presentation

    private let commands: (any PlaybackCommands)?

    public init(commands: (any PlaybackCommands)? = nil) {
        self.commands = commands
    }

    public var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            PlayerArtwork(size: 300, cornerRadius: 12)
                .shadow(radius: 20, y: 10)
                .padding(.top, 20)

            VStack(spacing: 6) {
                Text(nowPlaying.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(nowPlaying.artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            PlayerScrubber(commands: commands)
                .padding(.horizontal, 32)

            PlayerTransportControls(commands: commands)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlayerBackground())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 80 {
                        presentation.collapse()
                    }
                }
        )
    }
}

// MARK: - Components

/// Artwork, loaded asynchronously.
///
/// `AsyncImage` rather than Kingfisher: it is native, it is already async, and the player shows
/// exactly one image at a time. Kingfisher earns its place in scrolling grids, not here.
struct PlayerArtwork: View {
    @Environment(NowPlayingState.self) private var nowPlaying

    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: nowPlaying.artworkURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The position scrubber.
///
/// **The only view that reads `ProgressState`.** Keeping it that way is what stops a 30 Hz tick
/// from invalidating the rest of the player.
struct PlayerScrubber: View {
    @Environment(ProgressState.self) private var progress
    @Environment(NowPlayingState.self) private var nowPlaying

    let commands: (any PlaybackCommands)?

    @State private var isDragging = false
    @State private var draggedValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isDragging ? draggedValue : progress.currentTime },
                    set: { draggedValue = $0 }
                ),
                in: 0 ... max(nowPlaying.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        commands?.seek(to: draggedValue)
                    }
                }
            )

            HStack {
                Text(timeLabel(isDragging ? draggedValue : progress.currentTime))
                Spacer()
                Text(timeLabel(nowPlaying.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Previous / play-pause / next.
///
/// Reads only `TransportState`, which changes on user action rather than on a timer.
struct PlayerTransportControls: View {
    @Environment(TransportState.self) private var transport

    let commands: (any PlaybackCommands)?

    var body: some View {
        HStack(spacing: 40) {
            Button { commands?.skipToPrevious() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .disabled(!transport.canSkipBackward)
            .accessibilityLabel("Previous track")

            Button { commands?.togglePlayPause() } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")

            Button { commands?.skipToNext() } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .disabled(!transport.canSkipForward)
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

/// Play/pause alone, for the mini player.
struct TogglePlayPauseButton: View {
    @Environment(TransportState.self) private var transport
    let commands: (any PlaybackCommands)?

    var body: some View {
        Button { commands?.togglePlayPause() } label: {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")
    }
}

struct SkipForwardButton: View {
    @Environment(TransportState.self) private var transport
    let commands: (any PlaybackCommands)?

    var body: some View {
        Button { commands?.skipToNext() } label: {
            Image(systemName: "forward.fill")
                .font(.title3)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!transport.canSkipForward)
        .accessibilityLabel("Next track")
    }
}

/// Background tinted by the artwork's accent colour.
struct PlayerBackground: View {
    @Environment(NowPlayingState.self) private var nowPlaying

    var body: some View {
        LinearGradient(
            colors: [nowPlaying.accentColor.opacity(0.55), .black.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: nowPlaying.accentColor)
    }
}
