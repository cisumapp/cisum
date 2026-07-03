//
//  PlaylistCover.swift
//  Albums
//
//  Created by Aarav Gupta on 19/05/26.
//

#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import SwiftUI
import Utilities

// MARK: - Album Cover

public struct PlaylistCover: View {
    public var isCardExpanded: Bool
    @Bindable public var viewModel: PlaylistViewModel
    public let playlist: Playlist
    @Binding var showAllImages: Bool

    public init(isCardExpanded: Bool, viewModel: PlaylistViewModel, playlist: Playlist, showAllImages: Binding<Bool>) {
        self.isCardExpanded = isCardExpanded
        self.viewModel = viewModel
        self.playlist = playlist
        self._showAllImages = showAllImages
    }

    public var body: some View {
        ZStack {
            if showAllImages {
                // Stacked-card fan-out, tinted to the artwork palette so it reads as one object
                // instead of primary red/blue/green.
                Rectangle()
                    .foregroundStyle(viewModel.backgroundColor.opacity(0.9))
                    .offset(x: 30, y: -25)
                    .rotationEffect(.degrees(5))
                    .scaleEffect(0.8)
                    .opacity(isCardExpanded ? 0 : 1)
                    .overlay(isCardExpanded ? .clear : .black.opacity(0.5))
                    .shadow(radius: 5)

                Rectangle()
                    .foregroundStyle(viewModel.backgroundColor.opacity(0.7))
                    .offset(x: -30, y: 0)
                    .rotationEffect(.degrees(-15))
                    .scaleEffect(0.8)
                    .opacity(isCardExpanded ? 0 : 1)
                    .overlay(isCardExpanded ? .clear : .black.opacity(0.3))
                    .shadow(radius: 5)

                Rectangle()
                    .foregroundStyle(viewModel.backgroundColor.opacity(0.5))
                    .offset(x: 30, y: 25)
                    .rotationEffect(.degrees(15))
                    .scaleEffect(0.8)
                    .opacity(isCardExpanded ? 0 : 1)
                    .overlay(isCardExpanded ? .clear : .black.opacity(0.5))
                    .shadow(radius: 5)
            }

            Rectangle()
                .foregroundStyle(viewModel.backgroundColor)
                .overlay(isCardExpanded ? .clear : .black.opacity(0.1))

            if let artwork = playlist.artworkURLString {
                if artwork.hasPrefix("bundle://") {
                    let imageName = artwork.replacingOccurrences(of: "bundle://", with: "")
                    Image(imageName)
                        .resizable()
                        .padding(.top, isCardExpanded ? 50 : 0)
                } else if let displayURL = URL(string: artwork) {
                    ArtworkImage(url: displayURL, size: 400)
                        .padding(.top, isCardExpanded ? 50 : 0)
                }
            }

            if !isCardExpanded {
                Text(playlist.title)
                    .foregroundStyle(.blue.opacity(0.5))
                    .padding(4)
                    .background(.white)
//                    .fontWidth(.expanded)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if isCardExpanded {
                LinearGradient(
                    colors: [viewModel.backgroundColor, viewModel.backgroundColor.opacity(0.2), .clear, .clear, .clear, .clear, .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(playlist.title)
                                .font(.title)
//                                .fontWidth(.expanded)
                                .bold()

                            Text(playlist.createdAt.formatted())
//                                .fontWidth(.expanded)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding()
                }

                LinearGradient(
                    colors: [viewModel.backgroundColor, viewModel.backgroundColor.opacity(0.2), .clear, .clear, .clear, .clear, .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.playerExpandAnimation, value: isCardExpanded)
        .animation(.playerExpandAnimation, value: showAllImages)
        .task {
            guard let artwork = playlist.artworkURLString,
                  !artwork.hasPrefix("bundle://"),
                  let displayURL = URL(string: artwork)
            else { return }
            // Reuse the same best-quality URL the display renders, so palette extraction hits the
            // cached original instead of triggering a second download.
            let paletteSourceURL = ArtworkURL.best(from: displayURL) ?? displayURL
            await viewModel.fetchPaletteIfNeeded(from: paletteSourceURL)
        }
    }
}
#endif
