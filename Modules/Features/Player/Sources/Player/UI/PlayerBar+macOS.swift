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
import AVKit
import Models
import PlaybackCore
import SwiftUI

public struct PlayerBar: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.savedLibrary) private var savedLibrary
    @State private var isSaved = false

    public init() {}

    public var body: some View {
        HStack(spacing: 16) {
            nowPlaying
                .frame(width: 258, alignment: .leading)
            Spacer(minLength: 0)
            transport
            Spacer(minLength: 0)
            secondary
        }
        .padding(.leading, 10)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: Self.maxWidth)
        .background { surface }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .task(id: playerViewModel.currentVideoId) {
            isSaved = await savedLibrary?.isSaved(fingerprint: savableTrack.fingerprint) ?? false
        }
    }

    /// Widest the bar grows; the design's bar is 744pt in a 1280pt window.
    private static let maxWidth: CGFloat = 744

    private static let cornerRadius: CGFloat = 16

    /// The bar's own surface.
    ///
    /// `glassEffect` on its own resolves to a mid-grey in a dark window, which is too light
    /// for a bar that has to sit over artwork; the canvas colour laid over it brings it back to
    /// the same key as the sidebar. The hairline is what separates the bar from what is behind
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

    private var savableTrack: SavableTrack {
        SavableTrack(
            title: playerViewModel.currentTitle,
            artist: playerViewModel.currentArtist,
            artworkURL: playerViewModel.currentImageURL,
            sourceTrackID: playerViewModel.currentVideoId,
            youtubeMusicID: playerViewModel.currentVideoId
        )
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                (Text(playerViewModel.currentTitle)
                    + Text(playerViewModel.currentArtist.isEmpty ? "" : " - \(playerViewModel.currentArtist)")
                    .foregroundStyle(.secondary))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    // Which source is serving this, and what is known about the stream, on hover;
                    // the same rows are in Settings → Diagnostics.
                    .help(ActiveStreamDiagnostic.summary(playerViewModel.activeStreamState) ?? "")

                MacBarProgress()
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = playerViewModel.currentImageURL {
            ArtworkImage(url: url, size: 30)
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cisumChromeStrong)
                .frame(width: 30, height: 30)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 8) {
            transportButton("shuffle", help: "Playback mode", isActive: playerViewModel.playbackMode == .shuffle) {
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
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 24)
                    .contentTransition(.symbolEffect(.replace))
                    .contentShape(.rect)
            }
            .buttonStyle(PressScaleButtonStyle())
            .help(playerViewModel.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(playerViewModel.isPlaying ? "Pause" : "Play")

            transportButton("forward.fill", help: "Next") {
                playerViewModel.skipToNext()
            }
            .disabled(!playerViewModel.canSkipForward)

            transportButton(
                playerViewModel.playbackMode == .repeatOne ? "repeat.1" : "repeat",
                help: modeLabel,
                isActive: playerViewModel.playbackMode == .repeatAll || playerViewModel.playbackMode == .repeatOne
            ) {
                playerViewModel.cyclePlaybackMode()
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        help: String,
        size: CGFloat = 11,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? playerViewModel.currentAccentColor : .secondary)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
    }

    // MARK: - Secondary

    private var secondary: some View {
        HStack(spacing: 28) {
            transportButton(isSaved ? "star.fill" : "star", help: isSaved ? "Remove from Saved" : "Save", size: 13, isActive: isSaved) {
                let track = savableTrack
                Task { isSaved = await savedLibrary?.toggleSaved(track) ?? isSaved }
            }
            .disabled(playerViewModel.currentTitle.isEmpty)

            HStack(spacing: 16) {
                RoutePicker()
                    .frame(width: 20, height: 20)
                    .help("AirPlay")
                transportButton("speaker.wave.2", help: "Volume", size: 13) {}
            }

            HStack(spacing: 16) {
                transportButton("quote.bubble", help: "Lyrics", size: 13) {}
                transportButton("list.bullet", help: "Queue", size: 13) {}
            }
        }
    }

    // MARK: - Playback mode

    private var modeLabel: String {
        switch playerViewModel.playbackMode {
        case .off: "Repeat off"
        case .shuffle: "Shuffle"
        case .repeatAll: "Repeat all"
        case .repeatOne: "Repeat one"
        }
    }
}

/// A button that dips slightly while pressed, so a click is felt the moment it lands rather
/// than only when the action's result shows.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
    }
}

/// The system AirPlay picker, which lists the Mac's outputs and AirPlay devices.
private struct RoutePicker: NSViewRepresentable {
    func makeNSView(context _: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        return picker
    }

    func updateNSView(_: AVRoutePickerView, context _: Context) {}
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
    @State private var isHovering = false
    @State private var dragFraction: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.time(dragFraction.map { $0 * playerViewModel.duration } ?? progress.currentTime))
            GeometryReader { geo in
                let fraction = dragFraction ?? (playerViewModel.duration > 0 ? progress.currentTime / playerViewModel.duration : 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.1))
                    Capsule().fill(Color.primary.opacity(0.5))
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
                // Thin at rest, thicker under the pointer so it reads as something to grab.
                .frame(height: isHovering || dragFraction != nil ? 5 : 3)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(max($0.location.x / geo.size.width, 0), 1) }
                        .onEnded { _ in
                            if let dragFraction { playerViewModel.seek(to: dragFraction * playerViewModel.duration) }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 12)
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 1), value: isHovering)
            Text(Self.time(playerViewModel.duration))
        }
        .font(.system(size: 10, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
#endif
