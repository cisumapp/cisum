//
//  NowPlayingComponents.swift
//  cisum
//
//  Created by Aarav Gupta on 26/04/26.
//

import Aesthetics
import Kingfisher
import Models
import SwiftUI
import YouTubeSDK
import Tracks

// MARK: - Artwork Section

struct NowPlayingArtwork: View, Equatable {
    let size: CGSize
    let artworkURL: URL?
    let isLyricsVisible: Bool
    let isQueueVisible: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size &&
        lhs.artworkURL == rhs.artworkURL &&
        lhs.isLyricsVisible == rhs.isLyricsVisible &&
        lhs.isQueueVisible == rhs.isQueueVisible
    }

    var body: some View {
        GeometryReader { geometry in
            if isQueueVisible {
                NowPlayingQueueView()
                    .frame(width: geometry.size.width, height: geometry.size.width)
            } else if isLyricsVisible {
                LyricsView()
                    .frame(width: geometry.size.width, height: geometry.size.width)
            } else {
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 15)
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8), value: isLyricsVisible
        )
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8), value: isQueueVisible
        )
    }
}

// MARK: - Song Info Section

struct NowPlayingSongInfo: View, Equatable {
    let title: String
    let artist: String
    let isExplicit: Bool
    let videoId: String?

    @State private var isStreamQualitySheetPresented = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.isExplicit == rhs.isExplicit &&
        lhs.videoId == rhs.videoId
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if isExplicit {
                        Text("E")
                            .font(.caption2.bold())
                            .foregroundStyle(.primary.opacity(0.8))
                            .padding(4)
                            .background(Color.cisumChromeSubtle, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(artist)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    // Favorite action
                } label: {
                    Image(systemName: "star")
                }
                .sensoryFeedback(.impact, trigger: videoId)

                Button {
                    isStreamQualitySheetPresented = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .sheet(isPresented: $isStreamQualitySheetPresented) {
                    StreamQualityAndSourceSheet()
                }
            }
            .foregroundStyle(.primary)
            .font(.title2)
            .frame(alignment: .trailing)
        }
        .frame(height: 60)
        .padding(.top, 80)
    }
}

// MARK: - Progress Section (Fast updates isolated)

struct NowPlayingProgressSection: View {
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        MusicProgressScrubber(
            mediaID: playerViewModel.currentVideoId,
            currentTime: playerViewModel.currentTime,
            duration: playerViewModel.duration,
            onSeek: { newTime in
                playerViewModel.seek(to: newTime)
            }
        )
        .frame(height: 30)
    }
}

// MARK: - Controls Section

struct NowPlayingControls: View {
    @Environment(\.playerViewModel) private var playerViewModel
    let size: CGSize
    let safeArea: EdgeInsets

    var body: some View {
        VStack {
            NowPlayingProgressSection()

            Spacer(minLength: 0)

            HStack(spacing: size.width * 0.18) {
                PreviousButton()
                    .sensoryFeedback(.impact, trigger: playerViewModel.currentVideoId)

                TogglePlayPauseButton()
                    .disabled(playerViewModel.currentVideoId == nil)
                    .sensoryFeedback(.selection, trigger: playerViewModel.isPlaying)

                ForwardButton()
                    .sensoryFeedback(.impact, trigger: playerViewModel.currentVideoId)
            }
            .foregroundColor(.primary)

            Spacer(minLength: 0)

            VolumeSlider()
                .frame(height: 30)

            Spacer(minLength: 0)

            NowPlayingFooter(size: size, safeArea: safeArea)
        }
    }
}

// MARK: - Footer Section

struct NowPlayingFooter: View {
    @Environment(\.playerViewModel) private var playerViewModel
    let size: CGSize
    let safeArea: EdgeInsets

    var body: some View {
        HStack(alignment: .top, spacing: size.width * 0.18) {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    if let pvm = playerViewModel as? PlayerViewModel {
                        if pvm.isLyricsVisible {
                            pvm.isLyricsVisible = false
                        } else {
                            pvm.isQueueVisible = false
                            pvm.isLyricsVisible = true
                        }
                    }
                }
            } label: {
                Image(
                    systemName: playerViewModel.isLyricsVisible
                        ? "quote.bubble.fill" : "quote.bubble"
                )
                .font(.title2)
            }

//            AirPlayButton(activeTintColor: playerViewModel.currentAccentColor.opacity(0.2).uiColor)
            AirPlayButton()
                .opacity(0.2)
                .frame(width: 48, height: 48)
                .padding(.top, -13)

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    if let pvm = playerViewModel as? PlayerViewModel {
                        if pvm.isQueueVisible {
                            pvm.isQueueVisible = false
                        } else {
                            pvm.isLyricsVisible = false
                            pvm.isQueueVisible = true
                        }
                    }
                }
            } label: {
                Image(systemName: (playerViewModel as? PlayerViewModel)?.isQueueVisible == true ? "list.bullet" : "list.bullet")
                    .font(.title2)
            }
        }
        .foregroundColor(.secondary)
//        .blendMode(.overlay)
    }
}

// MARK: - Helper Components

struct NowPlayingInfoBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cisumChromeSubtle, in: Capsule())
            .foregroundStyle(.primary)
    }
}

// MARK: - Lyrics Section

struct LyricsView: View {
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        ZStack {
            switch playerViewModel.lyricsState {
            case .idle:
                Color.clear
            case .loading:
                ProgressView()
                    .tint(.primary)
                    .scaleEffect(1.5)
            case .synced:
                SyncedLyricsView()
            case .plain:
                PlainLyricsView()
            case let .unavailable(message):
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble.rtl.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.primary.opacity(0.15))

                    Text(message)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            }
        }
    }
}

struct SyncedLyricsView: View {
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(playerViewModel.syncedLyricsLines.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(
                            line: line,
                            isActive: isLineActive(line),
                            distance: distanceToActiveLine(index)
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 180)
                .padding(.horizontal, 20)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onChange(of: playerViewModel.currentSyncedLyricIndex) { _, newValue in
                if let index = newValue, playerViewModel.syncedLyricsLines.indices.contains(index) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
                        proxy.scrollTo(playerViewModel.syncedLyricsLines[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func isLineActive(_ line: TimedLyricLine) -> Bool {
        guard let index = playerViewModel.currentSyncedLyricIndex else { return false }
        return playerViewModel.syncedLyricsLines[index].id == line.id
    }

    private func distanceToActiveLine(_ index: Int) -> Int {
        guard let currentIndex = playerViewModel.currentSyncedLyricIndex else { return index }
        return abs(index - currentIndex)
    }
}

struct LyricLineView: View {
    let line: TimedLyricLine
    let isActive: Bool
    let distance: Int
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        Group {
            if isActive, let syllables = line.syllables, !syllables.isEmpty {
                syllablesText(currentTime: playerViewModel.currentTime)
            } else {
                Text(line.text)
                    .foregroundStyle(.primary.opacity(isActive ? 1.0 : opacityForDistance))
            }
        }
        .font(.system(size: 34, weight: .heavy, design: .rounded))
        .blur(radius: blurForDistance)
        .scaleEffect(scaleForDistance, anchor: .leading)
        .shadow(color: isActive ? .primary.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            playerViewModel.seek(to: line.timestamp)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isActive)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: distance)
    }

    private func syllablesText(currentTime: TimeInterval) -> Text {
        guard let syllables = line.syllables else { return Text(line.text) }

        var combinedText = Text("")
        for (index, syllable) in syllables.enumerated() {
            let isSyllableActive = currentTime >= syllable.timestamp
            let color = isSyllableActive ? Color.primary : Color.primary.opacity(0.3)

            var sylText = Text(syllable.text).foregroundStyle(color)
            if !syllable.isPartOfWord, index < syllables.count - 1 {
                sylText = sylText + Text(" ")
            }
            combinedText = combinedText + sylText
        }
        return combinedText
    }

    private var opacityForDistance: Double {
        switch distance {
        case 0: 1.0
        case 1: 0.5
        case 2: 0.25
        default: 0.15
        }
    }

    private var blurForDistance: CGFloat {
        switch distance {
        case 0: 0
        case 1: 1.5
        case 2: 3.0
        default: 4.5
        }
    }

    private var scaleForDistance: CGFloat {
        switch distance {
        case 0: 1.0
        case 1: 0.95
        case 2: 0.9
        default: 0.85
        }
    }
}

struct PlainLyricsView: View {
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(playerViewModel.plainLyricsText ?? "")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .multilineTextAlignment(.leading)
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Stream Quality & Source Sheet

struct StreamQualityAndSourceSheet: View {
    @Environment(\.playerViewModel) private var interfaceViewModel
    @Environment(\.dismiss) private var dismiss

    private var playerViewModel: PlayerViewModel? {
        interfaceViewModel as? PlayerViewModel
    }

    var body: some View {
        NavigationStack {
            if let playerViewModel {
                List {
                    Section(header: Text("Current Stream")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playerViewModel.currentStreamingServiceName.capitalized)
                                .font(.headline)
                            HStack {
                                NowPlayingInfoBadge(title: playerViewModel.currentAudioQualityLabel, systemImage: "waveform")
                                NowPlayingInfoBadge(title: playerViewModel.currentAudioCodecLabel, systemImage: "speaker.wave.2")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if !playerViewModel.playbackCandidates.isEmpty {
                        Section(header: Text("Available Alternatives")) {
                            ForEach(Array(playerViewModel.playbackCandidates.enumerated()), id: \.offset) { index, candidate in
                                Button {
                                    playerViewModel.switchPlaybackProvider(candidateIndex: index)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(candidate.providerID?.capitalized ?? "YouTube")
                                                .font(.subheadline.bold())
                                                .foregroundColor(index == playerViewModel.playbackCandidateIndex ? .cisumAccent : .primary)

                                            HStack {
                                                Text(playerViewModel.playbackLabels(for: candidate).quality)
                                                Text("•")
                                                Text(playerViewModel.playbackLabels(for: candidate).codec)
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if index == playerViewModel.playbackCandidateIndex {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.cisumAccent)
                                        }
                                    }
                                }
                                .tint(.primary)
                            }
                        }
                    }
                }
                .navigationTitle("Stream Source")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            } else {
                Text("Error: Invalid ViewModel")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Queue Section

struct NowPlayingQueueView: View {
    @Environment(\.playerViewModel) private var interfaceViewModel

    var body: some View {
        if let playerViewModel = interfaceViewModel as? PlayerViewModel {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(playerViewModel.queuePreviewItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playerViewModel.playQueueEntry(at: index)
                        } label: {
                            TrackListItem(
                                trackName: item.title,
                                artistName: item.subtitle,
                                duration: "",
                                artworkURL: item.artworkURL,
                                isExplicit: false
                            )
                            .background(
                                playerViewModel.currentQueuePreviewIndex == index 
                                    ? Color.primary.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            Color.clear
        }
    }
}
