@testable import Models
import XCTest

final class CisumLinkTests: XCTestCase {
    /// Both link forms (cisum:// custom scheme and https Universal Link) must round-trip.
    private func roundTrip(_ link: CisumLink, file: StaticString = #filePath, line: UInt = #line) {
        guard let custom = link.url(), let web = link.webURL() else {
            XCTFail("url()/webURL() returned nil", file: file, line: line)
            return
        }
        XCTAssertEqual(CisumLink.parse(custom), link, "cisum:// round-trip mismatch for \(custom)", file: file, line: line)
        XCTAssertEqual(CisumLink.parse(web), link, "https round-trip mismatch for \(web)", file: file, line: line)
    }

    func testSongRoundTrips() {
        roundTrip(.song(SharedSong(provider: .youtubeMusic, id: "abc123", title: "Song (Live)", artist: "Artist & Co", album: "Al/bum", artworkURL: URL(string: "https://img/x.jpg"), durationSeconds: 212, isExplicit: true, isrc: "USUM71234567")))
        roundTrip(.song(SharedSong(provider: .youtube, id: "v", title: "T", artist: "")))
    }

    func testShortenedPlaylistRoundTrips() {
        roundTrip(.playlist(.shortened(id: "aB3xQ", name: "love", author: "aarav")))
        roundTrip(.playlist(.shortened(id: "z9", name: nil, author: nil)))
    }

    func testWebHostVariantsParse() throws {
        let apex = try XCTUnwrap(URL(string: "https://cisum.studio/song?provider=youtube&id=v&title=t&artist=a"))
        let www = try XCTUnwrap(URL(string: "https://www.cisum.studio/song?provider=youtube&id=v&title=t&artist=a"))
        XCTAssertNotNil(CisumLink.parse(apex))
        XCTAssertEqual(CisumLink.parse(apex), CisumLink.parse(www))
    }

    func testImportedPlaylistRoundTrips() {
        roundTrip(.playlist(.imported(provider: .spotify, sourceID: "37i9dQ", name: "My Mix")))
        roundTrip(.playlist(.imported(provider: .youtube, sourceID: "PL123", name: nil)))
    }

    func testEmbeddedPlaylistRoundTrips() {
        let tracks = (0 ..< 12).map {
            SharedSong(provider: .youtubeMusic, id: "id\($0)", title: "Track \($0)", artist: "Artist \($0)", durationSeconds: Double($0 * 10))
        }
        roundTrip(.playlist(.embedded(name: "Saved", author: "me", sharedBy: "friend", tracks: tracks)))
    }

    func testArtistAlbumRoundTrip() {
        roundTrip(.artist(SharedArtist(provider: .spotify, id: "artist1", name: "Name", artworkURL: URL(string: "https://a/b.png"))))
        roundTrip(.album(SharedAlbum(provider: .spotify, id: "album1", name: "Album")))
    }

    func testGarbageDataRejected() throws {
        // Non-base64 / non-cisum inputs must not crash and must return nil.
        XCTAssertNil(try CisumLink.parse(XCTUnwrap(URL(string: "cisum://playlist?name=x&data=!!!notbase64!!!"))))
        XCTAssertNil(try CisumLink.parse(XCTUnwrap(URL(string: "https://example.com/song?id=1"))))
        XCTAssertNil(try CisumLink.parse(XCTUnwrap(URL(string: "cisum://bogushost?id=1"))))
    }

    func testNonHttpArtworkStripped() throws {
        let url = try XCTUnwrap(CisumLink.song(SharedSong(provider: .youtube, id: "v", title: "t", artist: "a")).url())
        // Inject a javascript: artwork and confirm it's dropped on parse.
        let hostile = URL(string: url.absoluteString + "&art=javascript:alert(1)")!
        if case let .song(song) = CisumLink.parse(hostile) {
            XCTAssertNil(song.artworkURL)
        } else {
            XCTFail("expected song")
        }
    }
}
