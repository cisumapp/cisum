//
//  PlayerBackground.swift
//  cisum
//
//  Created by Codex on 28/03/26.
//

#if os(iOS)
import Kingfisher
import SwiftUI

struct PlayerBackground: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    let isExpanded: Bool
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
                    .opacity(isExpanded ? 1 : 0)
            }
        }
        .clipShape(.rect(cornerRadius: dynamicCornerRadius))
        .frame(height: isExpanded ? nil : Constants.dynamicPlayerIslandHeight)
        .enableInjection()
    }
}

private extension PlayerBackground {
    var dynamicCornerRadius: CGFloat {
        isExpanded ? expandPlayerCornerRadius : collapsedPlayerCornerRadius
    }

    var expandPlayerCornerRadius: CGFloat {
        isFullExpanded ? 0 : UIScreen.deviceCornerRadius
    }

    var collapsedPlayerCornerRadius: CGFloat {
        Constants.dynamicPlayerIslandHeight / 2
    }
}
#endif
