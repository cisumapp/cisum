import Models

//
//  PlayerBackground.swift
//  cisum
//
//  Created by Aarav Gupta on 28/03/26.
//

#if os(iOS)
import Aesthetics
import Kingfisher
import SwiftUI
import Utilities

struct PlayerBackground: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.motionArtwork) private var motionArtwork
    /// The current album's animated artwork, once it is on the device.
    @State private var motionVideo: URL?

    let isPlayerExpanded: Bool
    let isFullExpanded: Bool
    var canBeExpanded: Bool = true
    /// Collapsed pill height. Drives both the frame and the collapsed corner
    /// radius so the background matches whatever the caller collapses to —
    /// the measured platter height on iOS 26, the island height on iOS 17/18.
    var collapsedHeight: CGFloat = Utilities.AppConstants.dynamicPlayerIslandHeight
    /// The Animated Artwork theme: the looping video instead of the record.
    var showsMotionArtwork = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.bar)

            if canBeExpanded {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .overlay {
                        ZStack {
                            playerViewModel.currentAccentColor
                                .scaleEffect(1.1)
                                .blur(radius: 10)

                            // The Animated Artwork theme: the video, or the cover until there is
                            // one, under the same dimming as the record so the controls read
                            // the same.
                            if showsMotionArtwork {
                                if let motionVideo, isPlayerExpanded {
                                    LoopingVideo(url: motionVideo)
                                        .transition(.opacity)
                                } else {
                                    ArtworkImage(url: playerViewModel.currentImageURL, size: 600)
                                        .scaledToFill()
                                        .transition(.opacity)
                                }
                            } else {
                            Aesthetics.Vinyl(
                                isPlaying: playerViewModel.isPlaying,
                                accentColor: playerViewModel.currentAccentColor,
                                content: {
                                    ArtworkImage(url: playerViewModel.currentImageURL, size: 400)
                                },
                                previous: {
                                    if let pvm = playerViewModel as? PlayerViewModel, let previous = pvm.previousQueuePreviewItem {
                                        KFImage(previous.artworkURL)
                                            .blur(radius: 100)
                                            .downsampling(size: CGSize(width: 256, height: 256))
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.clear
                                    }
                                },
                                upnext: {
                                    if let pvm = playerViewModel as? PlayerViewModel, let next = pvm.nextQueuePreviewItem {
                                        KFImage(next.artworkURL)
                                            .blur(radius: 100)
                                            .downsampling(size: CGSize(width: 256, height: 256))
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.clear
                                    }
                                },
                                previousTitle: (playerViewModel as? PlayerViewModel)?.previousQueuePreviewItem?.title,
                                previousSubtitle: (playerViewModel as? PlayerViewModel)?.previousQueuePreviewItem?.subtitle,
                                upnextTitle: (playerViewModel as? PlayerViewModel)?.nextQueuePreviewItem?.title,
                                upnextSubtitle: (playerViewModel as? PlayerViewModel)?.nextQueuePreviewItem?.subtitle
                            )
                            }

                            ZStack {
                                Color.black.opacity(0.1)
                                    .scaleEffect(1.8)
                                    .blur(radius: 100)

                                Color.black.opacity(0.35)
                            }
                            .compositingGroup()
                        }
                        .compositingGroup()
                    }
                    .opacity(isPlayerExpanded ? 1 : 0)
            }
        }
        .clipShape(.rect(cornerRadius: dynamicCornerRadius))
        .frame(height: isPlayerExpanded ? nil : collapsedHeight)
        // Every played track's album is fetched once and kept, and the next track's is fetched
        // ahead, so the video is usually waiting when the song starts.
        .task(id: showsMotionArtwork ? motionRequest : nil) {
            guard showsMotionArtwork, let motionArtwork, let motionRequest else {
                motionVideo = nil
                return
            }
            motionVideo = motionArtwork.cachedVideo(motionRequest)
            if motionVideo == nil, let fetched = await motionArtwork.fetch(motionRequest), !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.5)) { motionVideo = fetched }
            }
            if let next = playerViewModel.nextQueuePreviewItem {
                _ = await motionArtwork.fetch(MotionArtworkRequest(title: next.title, artist: next.subtitle))
            }
        }
    }

    private var motionRequest: MotionArtworkRequest? {
        guard let ref = playerViewModel.nowPlaying.ref, !ref.title.isEmpty else { return nil }
        return MotionArtworkRequest(
            title: ref.title,
            artist: ref.artist,
            album: ref.album,
            spotifyTrackID: ref.sourceID == "spotify" ? ref.sourceTrackID : nil
        )
    }
}

fileprivate extension PlayerBackground {
    var dynamicCornerRadius: CGFloat {
        isPlayerExpanded ? expandPlayerCornerRadius : collapsedPlayerCornerRadius
    }

    var expandPlayerCornerRadius: CGFloat {
        isFullExpanded ? 0 : UIScreen.deviceCornerRadius
    }

    var collapsedPlayerCornerRadius: CGFloat {
        collapsedHeight / 2
    }
}
#endif
