//
//  ProviderBindingContractTests.swift
//  ModelsTests
//
//  Pass 1 contracts: namespaced binding keys, ad-hoc (orphan) bindings, session expiry,
//  and the rule that a weak title/artist fingerprint cannot authorize a canonical merge.
//
//  Every assertion here holds against the CURRENT production model. Nothing in this file
//  requires a behaviour change; the production fixes those contracts imply (removing the
//  `songID` guard in `SongSourceStore.persist`, replacing the fingerprint-equality merge in
//  `CentralMediaStore`) are deferred to Pass 2.
//

import Foundation
@testable import Models
import SwiftData
import XCTest

@MainActor
final class ProviderBindingContractTests: XCTestCase {
    // MARK: - Helpers

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Artist.self, Album.self, Song.self, SongSource.self])
        let configuration = url.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func fetch(
        _ context: ModelContext,
        sourceID: String,
        trackID: String
    ) throws -> SongSource? {
        var descriptor = FetchDescriptor<SongSource>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.sourceTrackID == trackID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - I-2: namespaced keys do not collide

    /// A track id from one service must never resolve a binding on another service.
    func testBindingKeysAreNamespacedAndDoNotCollide() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(SongSource(sourceID: "youtube", sourceTrackID: "42"))
        context.insert(SongSource(sourceID: "youtube_music", sourceTrackID: "42"))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<SongSource>()).count, 2)
        XCTAssertEqual(try fetch(context, sourceID: "youtube", trackID: "42")?.sourceID, "youtube")
        XCTAssertEqual(try fetch(context, sourceID: "youtube_music", trackID: "42")?.sourceID, "youtube_music")
        XCTAssertNil(try fetch(context, sourceID: "tidal", trackID: "42"))
    }

    // MARK: - U-12 baseline: the frozen model set opens with no migration plan

    /// The migration baseline that `SchemaV1` will freeze: the current model set opens with **no**
    /// `SchemaMigrationPlan`, and a canonical `Song` with a bound `SongSource` round-trips across a
    /// store reopen. This is the pre-condition for U-12 (a versioned schema cannot be introduced
    /// over a baseline that does not already persist correctly).
    ///
    /// The *failure* half of U-12 — that an unopenable store must not present an empty library — is
    /// not testable here: it depends on changing `AppBootstrap`'s silent in-memory fallback, which is
    /// a Pass 2 production change. Deferred and documented.
    func testFrozenModelSetPersistsWithoutAMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("baseline.sqlite")

        do {
            let container = try makeContainer(url: storeURL)
            let context = ModelContext(container)
            let song = Song(title: "Ivy", normalizedTitle: "ivy", providerFingerprint: "ivy|frank ocean")
            context.insert(song)
            song.bind(sourceID: "youtube", sourceTrackID: "v1", durationSeconds: 249)
            try context.save()
        }

        do {
            let container = try makeContainer(url: storeURL)
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.title == "Ivy" })
            descriptor.fetchLimit = 1
            let restored = try XCTUnwrap(try context.fetch(descriptor).first)
            XCTAssertEqual(restored.sources.count, 1)
            XCTAssertEqual(restored.sources.first?.sourceTrackID, "v1")
            XCTAssertEqual(restored.sources.first?.song?.songID, restored.songID)
        }
    }

    // MARK: - U-4: the app-declared schema already covers SongSource

    /// The app's `AppBootstrap` schema lists `Song` but **not** `SongSource`. The U-4 "no schema
    /// change" claim therefore depends on `SongSource` being pulled into the schema transitively via
    /// `Song.sources`. This opens a container built from the app's model-set shape (Song without an
    /// explicit SongSource entry) and proves an orphan binding can still be written and read.
    func testAppDeclaredSchemaAlreadyIncludesSongSource() throws {
        let schema = Schema([Artist.self, Album.self, Song.self]) // deliberately omits SongSource
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let orphan = SongSource(sourceID: "youtube", sourceTrackID: "transitive")
        context.insert(orphan)
        try context.save()

        XCTAssertEqual(try fetch(context, sourceID: "youtube", trackID: "transitive")?.sourceTrackID, "transitive")
    }

    // MARK: - U-4: ad-hoc binding is representable, findable, and durable

    /// The ad-hoc binding contract: an orphan `SongSource` (no canonical `Song`) persists, is
    /// findable by `(sourceID, sourceTrackID)` alone — exactly what `SongSourceStore.lookup`
    /// predicates on — and survives a store reopen.
    func testOrphanBindingPersistsAndSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("contracts.sqlite")

        do {
            let container = try makeContainer(url: storeURL)
            let context = ModelContext(container)
            let orphan = SongSource(
                sourceID: "youtube",
                sourceTrackID: "adHocTrack",
                durationSeconds: 212,
                artworkURLString: "https://example.com/art.jpg"
            )
            context.insert(orphan)
            try context.save()
        }

        do {
            let container = try makeContainer(url: storeURL)
            let context = ModelContext(container)
            let found = try fetch(context, sourceID: "youtube", trackID: "adHocTrack")

            let unwrapped = try XCTUnwrap(found, "an orphan binding must be fetchable with no Song")
            XCTAssertNil(unwrapped.song, "an ad-hoc binding must not fabricate a canonical song")
            XCTAssertEqual(unwrapped.durationSeconds, 212)
        }
    }

    // MARK: - C-C-1: expired session refresh

    /// A cached URL is trusted only while fresh; expiry must force a re-resolve, and dropping the
    /// dead URL must not drop the identity.
    func testExpiredSessionIsRejectedAndRefreshedWithoutLosingBinding() throws {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "trackA")
        let now = Date()

        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/audio.m4a"))
        binding.cacheStream(
            url: url,
            mimeType: "audio/mp4",
            expiresAt: now.addingTimeInterval(60),
            headers: ["User-Agent": "cisum/1.0"],
            now: now
        )

        XCTAssertNotNil(binding.freshStreamURL(at: now.addingTimeInterval(30)), "fresh before expiry")
        XCTAssertNil(binding.freshStreamURL(at: now.addingTimeInterval(120)), "rejected after expiry")

        binding.invalidateStream()

        XCTAssertNil(binding.freshStreamURL(at: now), "an invalidated URL is gone")
        XCTAssertEqual(binding.sourceTrackID, "trackA", "the binding survives losing its URL")
        XCTAssertTrue(binding.allowsStreamCaching)
    }

    /// Transport details must travel with the session; losing the User-Agent makes a signed CDN URL
    /// fail silently.
    func testSessionHeadersRoundTripWithTheBinding() throws {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "trackB")
        let headers = ["User-Agent": "com.google.ios.youtube/19.29.1", "Accept": "*/*"]
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/b.m4a"))

        binding.cacheStream(
            url: url,
            mimeType: "audio/mp4",
            expiresAt: nil, // unknown expiry
            headers: headers,
            defaultLifetime: 3600
        )

        XCTAssertEqual(binding.cachedStreamHeaders, headers)
        XCTAssertNotNil(binding.cachedStreamExpiresAt, "unknown expiry must still apply a default")
    }

    // MARK: - I-4: a weak fingerprint cannot authorize a merge

    /// Identical normalized title and artist is candidate-discovery evidence only. With no agreed
    /// duration, the recording must not be merged into the canonical song.
    func testWeakFingerprintAloneDoesNotAuthorizeMerge() {
        let key = SongMatchKey(
            songID: "canonical",
            normalizedTitle: CanonicalSongReconciler.normalize("Ivy"),
            artistName: "Frank Ocean",
            durationSeconds: nil,
            albumName: nil
        )

        let incoming = IncomingTrack(
            provider: .youtube,
            providerTrackID: "differentRecording",
            title: "Ivy",
            artistName: "Frank Ocean",
            durationSeconds: nil
        )

        let score = CanonicalSongReconciler.score(incoming, against: key)
        XCTAssertLessThan(
            score,
            CanonicalSongReconciler.confidentThreshold,
            "title+artist alone must not reach the confident-merge threshold"
        )
    }

    /// The positive counterpart: with duration agreeing and the same version, the reconciler does
    /// reach the confident threshold — so the gate is not simply always-closed.
    func testAgreedEvidenceStillReachesTheConfidentThreshold() {
        let key = SongMatchKey(
            songID: "canonical",
            normalizedTitle: CanonicalSongReconciler.normalize("Ivy"),
            artistName: "Frank Ocean",
            durationSeconds: 249,
            albumName: nil
        )

        let incoming = IncomingTrack(
            provider: .youtube,
            providerTrackID: "sameRecording",
            title: "Ivy",
            artistName: "Frank Ocean",
            durationSeconds: 249
        )

        XCTAssertGreaterThanOrEqual(
            CanonicalSongReconciler.score(incoming, against: key),
            CanonicalSongReconciler.confidentThreshold
        )
    }

    /// A contradictory version must force separate records even when title/artist/duration agree.
    func testVersionConflictPreventsMerge() {
        let key = SongMatchKey(
            songID: "canonical",
            normalizedTitle: CanonicalSongReconciler.normalize("Hello"),
            artistName: "Adele",
            durationSeconds: 295,
            albumName: nil
        )

        let incoming = IncomingTrack(
            provider: .youtube,
            providerTrackID: "liveTake",
            title: "Hello (Live)",
            artistName: "Adele",
            durationSeconds: 295
        )

        XCTAssertLessThan(
            CanonicalSongReconciler.score(incoming, against: key),
            CanonicalSongReconciler.confidentThreshold
        )
    }
}
