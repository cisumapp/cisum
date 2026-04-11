//
//  PlayerBackground.swift
//  cisum
//
//  Created by Aarav Gupta on 28/03/26.
//

#if os(iOS)
import Kingfisher
import SwiftUI

struct PlayerBackground: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    let isPlayerExpanded: Bool
    let isFullExpanded: Bool
    var canBeExpanded: Bool = true
    
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

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

                            Vinyl {
                                KFImage(playerViewModel.currentImageURL)
                                    .downsampling(size: CGSize(width: 1400, height: 1400))
                                    .resizable()
                                    .scaledToFill()
                            } previous: {
                                Image(.notPlaying)
                                    .resizable()
                            } upnext: {
                                Image(.notPlaying)
                                    .resizable()
                            }

                            ZStack {
                                Color.white.opacity(0.1)
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
        .frame(height: isPlayerExpanded ? nil : Constants.dynamicPlayerIslandHeight)
        .enableInjection()
    }
}

private extension PlayerBackground {
    var dynamicCornerRadius: CGFloat {
        isPlayerExpanded ? expandPlayerCornerRadius : collapsedPlayerCornerRadius
    }

    var expandPlayerCornerRadius: CGFloat {
        isFullExpanded ? 0 : UIScreen.deviceCornerRadius
    }

    var collapsedPlayerCornerRadius: CGFloat {
        Constants.dynamicPlayerIslandHeight / 2
    }
}
#endif
