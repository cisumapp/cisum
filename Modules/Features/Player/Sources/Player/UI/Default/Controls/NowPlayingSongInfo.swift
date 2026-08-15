//
//  NowPlayingSongInfo.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import Aesthetics
import Models
import SwiftUI

struct NowPlayingSongInfo: View, Equatable {
    let title: String
    let artist: String
    let isExplicit: Bool
    let videoId: String?

    @State private var isAddToPlaylistPresented = false
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.savedLibrary) private var savedLibrary
    @State private var isSaved = false

    private var savableTrack: SavableTrack {
        SavableTrack(
            title: title,
            artist: artist,
            artworkURL: playerViewModel.currentImageURL,
            isExplicit: isExplicit,
            sourceTrackID: videoId,
            youtubeMusicID: videoId
        )
    }

    private var playbackModeTitle: String {
        switch playerViewModel.playbackMode {
        case .off: "Shuffle Off"
        case .shuffle: "Shuffle On"
        case .repeatAll: "Repeat Queue"
        case .repeatOne: "Repeat Song"
        }
    }

    private var playbackModeIcon: String {
        switch playerViewModel.playbackMode {
        case .off: "arrow.right"
        case .shuffle: "shuffle"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        }
    }

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
                        .foregroundStyle(.white)

                    if isExplicit {
                        Text("E")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.white.opacity(0.8))
                            .padding(4)
                            .background(Color.cisumChromeSubtle, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(artist)
                    .font(.headline)
                    .foregroundColor(Color.white.opacity(0.8))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    Task {
                        guard let savedLibrary, videoId != nil else { return }
                        isSaved = await savedLibrary.toggleSaved(savableTrack)
                    }
                } label: {
                    Image(systemName: isSaved ? "star.fill" : "star")
                }
                .sensoryFeedback(.impact, trigger: videoId)
                .disabled(videoId == nil)

                Menu {
                    // Cycles off → shuffle → repeat queue → repeat one. Stays open so it can
                    // be tapped repeatedly (Apple Music style) via menuActionDismissBehavior.
                    Button {
                        playerViewModel.cyclePlaybackMode()
                    } label: {
                        Label(playbackModeTitle, systemImage: playbackModeIcon)
                    }
                    .menuActionDismissBehavior(.disabled)

                    if let sharedSong = SharedSong(savable: savableTrack), let shareURL = CisumLink.song(sharedSong).webURL() {
                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        isAddToPlaylistPresented = true
                    } label: {
                        Label("Add to Playlist", systemImage: "text.badge.plus")
                    }
                    .disabled(videoId == nil)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .sheet(isPresented: $isAddToPlaylistPresented) {
                    AddToPlaylistSheet(track: savableTrack)
                }
            }
            .foregroundStyle(Color.white)
            .font(.title2)
            .frame(alignment: .trailing)
        }
        .frame(height: 60)
        .padding(.top, 80)
        .task(id: videoId) {
            guard let savedLibrary, videoId != nil else {
                isSaved = false
                return
            }
            isSaved = await savedLibrary.isSaved(fingerprint: savableTrack.fingerprint)
        }
    }
}
#endif
