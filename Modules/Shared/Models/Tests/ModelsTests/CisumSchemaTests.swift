//
//  CisumSchemaTests.swift
//  ModelsTests
//
//  Pass 2 (U-12): the versioned persistent schema, and the fact that opening through the migration
//  plan retains canonical songs, their provider representations, and ad-hoc orphan bindings.
//
//  Every persistent model lives in this package, so these run against the *real* `CisumSchemaV1`
//  rather than a stand-in.
//

import Foundation
@testable import Models
import SwiftData
import XCTest

@MainActor
final class CisumSchemaTests: XCTestCase {
    private func makeContainer(url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CisumSchemaV1.models),
            migrationPlan: CisumMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("cisum.sqlite")
    }

    // MARK: - Shape

    func testSchemaV1DescribesTheWholeStore() {
        let names = CisumSchemaV1.models.map { String(describing: $0) }

        XCTAssertEqual(names.count, 15, "the versioned schema must list every persistent model")
        XCTAssertTrue(names.contains("Song"))
        XCTAssertTrue(names.contains("SongSource"), "SongSource must be explicit, not implied by a relationship")
        XCTAssertTrue(names.contains("QueueStateEntry"))

        XCTAssertEqual(CisumSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testMigrationPlanHasNoCustomStages() {
        XCTAssertEqual(CisumMigrationPlan.schemas.count, 1)
        XCTAssertTrue(
            CisumMigrationPlan.stages.isEmpty,
            "no non-additive change is planned, so a custom stage would be cost without benefit"
        )
    }

    // MARK: - Retention through the plan

    /// Opening an existing store through `CisumMigrationPlan` must retain the canonical song and its
    /// provider representation, and must leave an ad-hoc orphan binding intact.
    func testStoreReopensThroughThePlanAndRetainsRecords() throws {
        let url = try temporaryStoreURL()

        do {
            let container = try makeContainer(url: url)
            let context = ModelContext(container)

            let song = Song(title: "Ivy", normalizedTitle: "ivy", providerFingerprint: "ivy|frank ocean")
            context.insert(song)
            song.bind(sourceID: "youtube", sourceTrackID: "v1", durationSeconds: 249)

            // An ad-hoc binding: a representation with no canonical song.
            context.insert(SongSource(sourceID: "youtube", sourceTrackID: "orphanAdHoc"))

            try context.save()
        }

        do {
            let container = try makeContainer(url: url)
            let context = ModelContext(container)

            var songDescriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.title == "Ivy" })
            songDescriptor.fetchLimit = 1
            let restored = try XCTUnwrap(try context.fetch(songDescriptor).first)
            XCTAssertEqual(restored.sources.count, 1)
            XCTAssertEqual(restored.sources.first?.sourceTrackID, "v1")
            XCTAssertEqual(restored.sources.first?.song?.songID, restored.songID)

            var orphanDescriptor = FetchDescriptor<SongSource>(
                predicate: #Predicate { $0.sourceTrackID == "orphanAdHoc" }
            )
            orphanDescriptor.fetchLimit = 1
            let orphan = try XCTUnwrap(try context.fetch(orphanDescriptor).first)
            XCTAssertNil(orphan.song, "an ad-hoc binding must survive with no canonical song")
            XCTAssertEqual(orphan.sourceID, "youtube")
        }
    }
}
