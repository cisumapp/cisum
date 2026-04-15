//
//  DynamicPlayerIsland.swift
//  cisum
//
//  Created by Aarav Gupta on 13/03/26.
//

import Kingfisher
import SwiftUI

struct DynamicPlayerIsland: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    
    
    @Binding var isPlayerExpanded: Bool
    var namespace: Namespace.ID
    
#if DEBUG
    @ObserveInjection var forceRedraw
#endif
    
    var body: some View {
        nowPlaying
            .frame(height: Constants.dynamicPlayerIslandHeight)
            .contentShape(.rect)
            .transformEffect(.identity)
            .onTapGesture {
                guard !isPlayerExpanded else { return }
                withAnimation(.playerExpandAnimation) {
                    isPlayerExpanded = true
                }
            }
            .enableInjection()
    }
}

private extension DynamicPlayerIsland {
    @ViewBuilder
    var artwork: some View {
        ZStack {
            if !isPlayerExpanded {
                KFImage(playerViewModel.currentImageURL)
                    .downsampling(size: CGSize(width: 80, height: 80))
                    .resizable()
                    .frame(width: 38, height: 38)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.circle)
            }
        }
    }
    
    var nowPlaying: some View {
        HStack(spacing: 12) {
            artwork

            Text(playerViewModel.currentTitle)
                .fontWeight(.semibold)

            Spacer()

            HStack(spacing: 14) {
                previous

                togglePlayPause

                next
            }
            .font(.title3)
            .fontWeight(.bold)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
    }
    
    var previous: some View {
        Button {
            playerViewModel.skipToPrevious()
        } label: {
            Image(systemName: "backward.fill")
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
        }
        .buttonStyle(.plain)
        .disabled(playerViewModel.currentVideoId == nil)
        .accessibilityLabel(playerViewModel.isPlaying ? "Pause" : "Play")
    }
    
    var next: some View {
        Button {
            playerViewModel.skipToNext()
        } label: {
            Image(systemName: "forward.fill")
        }
        .buttonStyle(.plain)
        .disabled(!playerViewModel.canSkipForward)
        .opacity(playerViewModel.canSkipForward ? 1 : 0.35)
        .accessibilityLabel("Next")
    }
}
