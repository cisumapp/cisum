//
//  ArtistDiscography.swift
//  Artists
//
//  Created by Aarav Gupta on 01/05/26.
//

import Aesthetics
import Albums
import Models
import SwiftData
import SwiftUI

struct ArtistDiscography: View {
    let artist: Artist

    @Query private var albums: [Album]

    init(artist: Artist) {
        self.artist = artist
        let artistID = artist.artistID
        _albums = Query(filter: #Predicate<Album> { $0.primaryArtistID == artistID })
    }

    var body: some View {
        if !albums.isEmpty {
            VStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 4) {
                    Text("Discography")
                        .font(.title)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                }
                .bold()
                .legibleForeground(.primary)
                .padding(.horizontal)
                .padding(.bottom)

                // Edge to edge: each `AlbumCard` carries its own side padding, so the shelf
                // scrolls under the screen's edge instead of clipping inside an inset.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(albums, id: \.albumID) { album in
                            AlbumCard(album: album)
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .padding(.vertical)
        }
    }
}
