import XCTest
@testable import Models

final class ReconcilerTests: XCTestCase {
    private func track(_ t: String, _ a: String, isrc: String? = nil, dur: Double? = nil,
                       album: String? = nil, p: MediaProvider = .spotify) -> IncomingTrack {
        IncomingTrack(provider: p, providerTrackID: "id", title: t, artistName: a,
                      albumName: album, isrc: isrc, durationSeconds: dur)
    }

    private func key(_ t: String, _ a: String, dur: Double? = nil, album: String? = nil) -> SongMatchKey {
        SongMatchKey(songID: "s", normalizedTitle: CanonicalSongReconciler.normalize(t),
                     artistName: a, durationSeconds: dur, albumName: album)
    }

    func test_normalize_strips_remaster_and_feat() {
        XCTAssertEqual(CanonicalSongReconciler.normalize("Song (2009 Remaster)"),
                       CanonicalSongReconciler.normalize("Song"))
        XCTAssertEqual(CanonicalSongReconciler.normalize("Song feat. X"),
                       CanonicalSongReconciler.normalize("Song"))
        XCTAssertEqual(CanonicalSongReconciler.normalize("Song - Remastered"),
                       CanonicalSongReconciler.normalize("song"))
    }

    func test_exact_title_artist_duration_scores_high() {
        XCTAssertGreaterThanOrEqual(
            CanonicalSongReconciler.score(track("Hello", "Adele", dur: 295),
                                          against: key("Hello", "Adele", dur: 295)),
            0.85)
    }

    func test_title_artist_album_duration_scores_higher() {
        XCTAssertGreaterThanOrEqual(
            CanonicalSongReconciler.score(track("Hello", "Adele", dur: 295, album: "25"),
                                          against: key("Hello", "Adele", dur: 295, album: "25")),
            0.95)
    }

    func test_different_song_scores_low() {
        XCTAssertLessThan(
            CanonicalSongReconciler.score(track("Thriller", "MJ", dur: 357),
                                          against: key("Hello", "Adele", dur: 295)),
            0.5)
    }

    func test_live_version_mismatch_scores_zero() {
        // same title/artist/duration but one is a live version → must not dedup
        XCTAssertLessThan(
            CanonicalSongReconciler.score(track("Hello (Live)", "Adele", dur: 295),
                                          against: key("Hello", "Adele", dur: 295)),
            0.5)
    }

    func test_base_provider_prefers_higher_rank() {
        XCTAssertEqual(CanonicalSongReconciler.mergedBaseProvider(current: .youtube, incoming: .appleMusic), .appleMusic)
        XCTAssertEqual(CanonicalSongReconciler.mergedBaseProvider(current: .spotify, incoming: .youtube), .spotify)
        XCTAssertEqual(CanonicalSongReconciler.mergedBaseProvider(current: nil, incoming: .youtube), .youtube)
    }
}
