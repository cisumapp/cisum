//
//  DynamicPlayerIsland+macOS.swift
//  cisum
//
//  Created by Aarav Gupta on 13/03/26.
//

import Aesthetics
import Kingfisher
import SwiftUI

#if os(macOS)
public struct DynamicPlayerIsland: View {
    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(\.isDynamicPlayerExpanded) private var isDynamicPlayerExpanded

    public init() {}

    @State private var isHovering = false
    @State private var isLyricsExpanded = false
    @Namespace private var namespace

    var isMiniPlayerExpanded: Bool {
        get { isDynamicPlayerExpanded.wrappedValue }
        nonmutating set { isDynamicPlayerExpanded.wrappedValue = newValue }
    }

    public var body: some View {
        surface
            .aspectRatio(isLyricsExpanded ? (1 / 2.5) : isHovering ? 5 / 3 : 5, contentMode: .fit)
            .frame(maxHeight: panelHeight)
            .overlay {
                islandContent
            }
            .onHover { hovering in
                withAnimation(.playerExpandAnimation) {
                    isHovering = hovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .animation(.playerExpandAnimation, value: presentationState)
            .environment(\.isDynamicPlayerExpanded, $isLyricsExpanded)
    }
}

fileprivate extension DynamicPlayerIsland {
    enum PresentationState {
        case compact
        case controls
        case lyrics
    }

    enum Layout {
        static let compactWidth: CGFloat = 260
        static let compactHeight: CGFloat = 60
        static let expandedWidth: CGFloat = 300
        static let expandedHeight: CGFloat = 180
        static let lyricsWidth: CGFloat = 425
    }

    var presentationState: PresentationState {
        if isLyricsExpanded {
            return .lyrics
        }

        return isHovering ? .controls : .compact
    }

    var panelWidth: CGFloat {
        switch presentationState {
        case .compact:
            Layout.compactWidth
        case .controls:
            Layout.expandedWidth
        case .lyrics:
            Layout.lyricsWidth
        }
    }

    var panelHeight: CGFloat {
        switch presentationState {
        case .compact:
            Layout.compactHeight
        case .controls:
            Layout.expandedHeight
        case .lyrics:
            .infinity
        }
    }

    @ViewBuilder
    var surface: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: isHovering ? 21 : (isLyricsExpanded ? 21 : 50))
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: isHovering ? 21 : (isLyricsExpanded ? 21 : 50))
                )
        } else {
            RoundedRectangle(
                cornerRadius: isHovering ? 21 : (isLyricsExpanded ? 21 : 50), style: .circular
            )
            .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    var islandContent: some View {
        switch presentationState {
        case .compact:
            compactContent
        case .controls:
            controlsContent
        case .lyrics:
            lyricsContent
        }
    }

    var compactContent: some View {
        HStack(spacing: 10) {
            artwork(size: 44, cornerRadius: 22)

            songInfo(
                titleFont: .system(size: 14, weight: .semibold),
                artistFont: .system(size: 12, weight: .semibold),
                titleLineLimit: 1,
                artistLineLimit: 1
            )

            Spacer(minLength: 6)

            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    var controlsContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artwork(size: 48, cornerRadius: 10)

                songInfo(
                    titleFont: .system(size: 15, weight: .semibold),
                    artistFont: .system(size: 14, weight: .semibold),
                    titleLineLimit: 1,
                    artistLineLimit: 1
                )
            }

            playbackProgress

            playbackControls
        }
        .padding(12)
    }

    var lyricsContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artwork(size: 48, cornerRadius: 10)

                songInfo(
                    titleFont: .system(size: 15, weight: .semibold),
                    artistFont: .system(size: 14, weight: .semibold),
                    titleLineLimit: 1,
                    artistLineLimit: 1
                )

                Spacer(minLength: 6)
            }

            lyricsLines

            playbackProgress

            playbackControls
        }
        .padding(12)
    }

    func artwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        KFImage(playerViewModel.currentImageURL)
            .placeholder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.cisumChromeSubtle)
            }
            .downsampling(size: CGSize(width: size * 2, height: size * 2))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.cisumChromeBorder, lineWidth: 1)
            }
            .matchedGeometryEffect(id: "Artwork", in: namespace)
    }

    func songInfo(
        titleFont: Font,
        artistFont: Font,
        titleLineLimit: Int,
        artistLineLimit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nowPlayingTitle)
                .font(titleFont)
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)

            Text(nowPlayingArtist)
                .font(artistFont)
                .foregroundStyle(.secondary)
                .lineLimit(artistLineLimit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .matchedGeometryEffect(id: "SongInfo", in: namespace)
    }

    var playbackProgress: some View {
        MusicProgressScrubber(
            mediaID: playerViewModel.currentVideoId,
            currentTime: playerViewModel.currentTime,
            duration: playerViewModel.duration,
            onSeek: { newTime in
                playerViewModel.seek(to: newTime)
            }
        )
    }

    var playbackControls: some View {
        HStack(spacing: 26) {
            lyricsToggle

            previous

            togglePlayPause

            next

            volumeButton
        }
        .foregroundStyle(.primary)
    }

    var lyricsLines: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if !playerViewModel.syncedLyricsLines.isEmpty {
                    ForEach(Array(playerViewModel.syncedLyricsLines.enumerated()), id: \.offset) {
                        index, line in
                        let isCurrentLyric = index == playerViewModel.currentSyncedLyricIndex

                        Text(line.text)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary.opacity(isCurrentLyric ? 0.98 : 0.68))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(Array(displayLyrics.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.68))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var nowPlayingTitle: String {
        let cleaned = playerViewModel.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Not Playing" : cleaned
    }

    var nowPlayingArtist: String {
        let cleaned = playerViewModel.currentArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown Artist" : cleaned
    }

    var displayLyrics: [String] {
        let syncedLines = playerViewModel.syncedLyricsLines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !syncedLines.isEmpty {
            return syncedLines
        }

        if let plainLyricsText = playerViewModel.plainLyricsText {
            let plainLines =
                plainLyricsText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            if !plainLines.isEmpty {
                return plainLines
            }
        }

        switch playerViewModel.lyricsState {
        case .loading:
            return ["Loading lyrics..."]
        case let .unavailable(message):
            return [message]
        default:
            return ["Lyrics unavailable for this track."]
        }
    }

    var lyricsToggle: some View {
        Button {
            withAnimation(.playerExpandAnimation) {
                isLyricsExpanded.toggle()
            }
        } label: {
            Image(systemName: isLyricsExpanded ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 20, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLyricsExpanded ? "Hide lyrics" : "Show lyrics")
    }

    var previous: some View {
        Button {
            playerViewModel.skipToPrevious()
        } label: {
            Image(systemName: "backward.fill")
                .font(.system(size: 23, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(!playerViewModel.canSkipBackward)
        .opacity(playerViewModel.canSkipBackward ? 1 : 0.35)
        .accessibilityLabel("Previous")
    }

    var togglePlayPause: some View {
        Button {
            playerViewModel.togglePlayPause()
        } label: {
            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 34, weight: .bold))
        }
        .buttonStyle(.plain)
        .disabled(playerViewModel.currentVideoId == nil)
        .opacity(playerViewModel.currentVideoId == nil ? 0.35 : 1)
        .accessibilityLabel(playerViewModel.isPlaying ? "Pause" : "Play")
    }

    var next: some View {
        Button {
            playerViewModel.skipToNext()
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 23, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(!playerViewModel.canSkipForward)
        .opacity(playerViewModel.canSkipForward ? 1 : 0.35)
        .accessibilityLabel("Next")
    }

    var volumeButton: some View {
        Button {} label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio")
    }
}
#endif
