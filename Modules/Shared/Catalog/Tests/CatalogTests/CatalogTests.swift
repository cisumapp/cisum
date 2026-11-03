@testable import Catalog
import Foundation
import Testing
import iTunesKit
import YouTubeSDK

struct CatalogTests {
    private func release(_ title: String, single: Bool = false, year: String) -> Catalog.ITunesRelease {
        .init(title: title, isSingle: single, year: year, genre: "Alternative", artworkURL: URL(string: "https://apple.test/\(title.count)"), collectionID: title.count)
    }

    @Test("YouTube's releases keep their order and gain iTunes' year, genre and artwork; the rest are appended")
    func mergeFillsAndAppends() {
        let youtube = [CatalogAlbum(title: "OK Computer", youtubeBrowseID: "yt-ok")]
        let itunes = [
            release("Kid A", year: "2000"),
            release("OK COMPUTER", year: "1997"),
            release("Lift", single: true, year: "2017"),
        ]
        let merged = Catalog.merge(albums: youtube, singles: [], itunes: itunes)

        #expect(merged.albums.map(\.title) == ["OK Computer", "Kid A"])
        #expect(merged.albums[0].year == "1997")
        #expect(merged.albums[0].genre == "Alternative")
        #expect(merged.albums[0].youtubeBrowseID == "yt-ok")
        #expect(merged.albums[0].artworkURL?.absoluteString == "https://apple.test/11")
        #expect(merged.singles.map(\.title) == ["Lift"])
    }

    @Test("iTunes names singles and EPs with a suffix; the release drops it")
    func singleSuffix() throws {
        let data = Data(#"{"wrapperType":"collection","collectionName":"Lift - Single","collectionId":1,"releaseDate":"2017-06-23T07:00:00Z","artworkUrl100":"https://is1.mzstatic.com/a/100x100bb.jpg"}"#.utf8)
        let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
        let release = try #require(Catalog.ITunesRelease(result))
        #expect(release.title == "Lift")
        #expect(release.isSingle)
        #expect(release.year == "2017")
        #expect(release.artworkURL?.absoluteString.contains("1000x1000bb") == true)
    }

    @Test("Live: an artist's page fills from YouTube Music and iTunes with no sign-in")
    func liveArtist() async {
        let artist = await Catalog(youtube: YouTubeMusicClient()).artist(named: "Radiohead")
        #expect(artist.youtubeBrowseID != nil)
        #expect(artist.about?.isEmpty == false)
        #expect(artist.photoURL != nil)
        #expect(artist.genre != nil)
        #expect(!artist.topSongs.isEmpty)
        #expect(artist.albums.count > 8)
        #expect(artist.albums.allSatisfy { $0.year != nil })
        #expect(!artist.singles.isEmpty)
        #expect(!artist.videos.isEmpty)
        #expect(!artist.playlists.isEmpty)
        #expect(!artist.similar.isEmpty)

        if let playlist = artist.playlists.first {
            #expect(await !Catalog(youtube: YouTubeMusicClient()).playlistTracks(youtubeBrowseID: playlist.youtubeBrowseID).isEmpty)
        }
    }
}
