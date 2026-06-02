//
//  ArtistTopSongs.swift
//  Artists
//
//  Created by Aarav Gupta on 01/05/26.
//

import Models
import SwiftData
import SwiftUI
import Tracks

struct ArtistTopSongs: View {
    let artist: Artist
    let onPlayTrack: (Int) -> Void

    @Query private var topTracks: [Song]

    init(artist: Artist, onPlayTrack: @escaping (Int) -> Void) {
        self.artist = artist
        self.onPlayTrack = onPlayTrack
        let artistID = artist.artistID
        _topTracks = Query(filter: #Predicate<Song> { $0.primaryArtistID == artistID })
    }

    var body: some View {
        if !topTracks.isEmpty {
            VStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 4) {
                    Text("Top Songs")
                        .font(.title)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                }
                .bold()
                .padding(.bottom)

                ForEach(Array(topTracks.enumerated()), id: \.element.songID) { index, track in
                    Button {
                        onPlayTrack(index)
                    } label: {
                        TrackListItem(
                            trackName: track.title,
                            artistName: track.primaryArtistName ?? artist.displayName,
                            duration: formatDuration(track.durationSeconds),
                            artworkURL: (track.artworkURLString ?? artist.artworkURLString).flatMap { URL(string: $0) },
                            isExplicit: track.isExplicit
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
