//
//  DynamicPlayerIsland.swift
//  cisum
//
//  Created by Aarav Gupta on 13/03/26.
//

import Kingfisher
import SwiftUI

struct DynamicPlayerIsland: View {
#if os(iOS)
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
    //#elseif os(macOS)
    //    @State private var isHovered: Bool = false
    //    @Namespace private var namespace
    //
    //    #if DEBUG
    //    @ObserveInjection var forceRedraw
    //    #endif
    //
    //    var body: some View {
    //        ZStack {
    //            if isHovered {
    //                if #available(macOS 26.0, *) {
    //                    RoundedRectangle(cornerRadius: 24)
    //                        .fill(.clear)
    //                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    //                        .matchedGeometryEffect(id: "GLASS", in: namespace)
    //                        .frame(height: 180)
    //                        .overlay {
    //                            VStack {
    //                                HStack {
    //                                    RoundedRectangle(cornerRadius: 12)
    //                                        .matchedGeometryEffect(id: "Artwork", in: namespace)
    //                                        .frame(width: 74, height: 74)
    //                                    VStack(alignment: .leading) {
    //                                        Text("Now Playing")
    //                                            .font(.title3)
    //                                            .fontWeight(.semibold)
    //                                        Text("Artist")
    //                                            .font(.subheadline)
    //                                            .foregroundStyle(.secondary)
    //                                    }
    //                                    Spacer()
    //                                }
    //                                .padding()
    //
    //                                Spacer()
    //
    //                                HStack {
    //                                    Image(systemName: "backward.fill")
    //                                    Image(systemName: "play.fill")
    //                                    Image(systemName: "forward.fill")
    //                                }
    //                                .font(.title)
    //                                .padding()
    //                            }
    //                        }
    //                }
    //            } else {
    //                if #available(macOS 26.0, *) {
    //                    RoundedRectangle(cornerRadius: 40)
    //                        .fill(.secondary.opacity(0.06))
    //                        .glassEffect(.regular)
    //                        .matchedGeometryEffect(id: "GLASS", in: namespace)
    //                        .frame(height: 70)
    //                        .overlay {
    //                            HStack {
    //                                Circle()
    //                                    .matchedGeometryEffect(id: "Artwork", in: namespace)
    //                                    .frame(width: 44, height: 44)
    //                                Text("Now Playing")
    //                                    .fontWeight(.semibold)
    //                                Spacer()
    //                            }
    //                            .padding(12)
    //                        }
    //                }
    //            }
    //        }
    //        .padding()
    //        .onHover { hovering in
    //            withAnimation(.bouncy) {
    //                isHovered = hovering
    //            }
    //        }
    //        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    //        .enableInjection()
    //    }
#endif
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
