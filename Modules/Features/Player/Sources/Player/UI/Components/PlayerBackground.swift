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
    @Environment(\.playerViewModel) private var playerViewModel

    let isPlayerExpanded: Bool
    let isFullExpanded: Bool
    var canBeExpanded: Bool = true

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

                            Aesthetics.Vinyl(
                                isPlaying: playerViewModel.isPlaying,
                                accentColor: playerViewModel.currentAccentColor,
                                content: {
                                    KFImage(playerViewModel.currentImageURL)
                                        .resizable()
                                        .scaledToFill()
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
        .frame(height: isPlayerExpanded ? nil : Utilities.AppConstants.dynamicPlayerIslandHeight)
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
        Utilities.AppConstants.dynamicPlayerIslandHeight / 2
    }
}
#endif
