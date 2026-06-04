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
                Rectangle()
                    .foregroundStyle(.red)
                    .offset(x: 30, y: -25)
                    .rotationEffect(.degrees(5))
                    .scaleEffect(0.8)
                    .opacity(isCardExpanded ? 0 : 1)
                    .overlay(isCardExpanded ? .clear : .black.opacity(0.5))
                    .shadow(radius: 5)

                Rectangle()
                    .foregroundStyle(.blue)
                    .offset(x: -30, y: 0)
                    .rotationEffect(.degrees(-15))
                    .scaleEffect(0.8)
                    .opacity(isCardExpanded ? 0 : 1)
                    .overlay(isCardExpanded ? .clear : .black.opacity(0.3))
                    .shadow(radius: 5)

                Rectangle()
                    .foregroundStyle(.green)
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
                    KFImage(displayURL)
                        .resizable()
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
        .animation(.smooth(duration: 0.3, extraBounce: 0), value: isCardExpanded)
        .animation(.smooth(duration: 0.3, extraBounce: 0), value: showAllImages)
        .task {
            guard let artwork = playlist.artworkURLString,
                  !artwork.hasPrefix("bundle://"),
                  let displayURL = URL(string: artwork)
            else { return }
            let paletteURL = ImageColorExtractor.paletteURL(from: displayURL)
            await viewModel.fetchPaletteIfNeeded(from: paletteURL)
        }
    }
}
#endif
