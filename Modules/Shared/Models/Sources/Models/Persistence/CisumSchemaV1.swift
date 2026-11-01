//
//  CisumSchemaV1.swift
//  Models
//
//  The persistent schema, versioned (decision U-12).
//
//  Before this, `AppBootstrap` built the container from a raw `Schema([...])` list and relied on
//  SwiftData's implicit migration, with any failure silently falling back to an in-memory store.
//  A versioned schema makes the shape explicit and gives future migrations a named predecessor.
//

import Foundation
import SwiftData

/// The persistent schema as of the architecture reset.
///
/// Every `@Model` type cisum persists, in one place. `SongSource` is listed explicitly rather than
/// being pulled in transitively through `Song.sources`, so the versioned schema describes the whole
/// store rather than most of it.
public enum CisumSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            SearchHistoryEntry.self,
            ListeningHistoryEntry.self,
            MediaCacheEntry.self,
            SearchCacheHintEntry.self,
            SpotifyCacheEntry.self,
            Playlist.self,
            PlaylistItem.self,
            PlaylistImportJobEntry.self,
            PlaylistImportTrackEntry.self,
            PlaylistImportCandidateEntry.self,
            Artist.self,
            Album.self,
            Song.self,
            SongSource.self,
            QueueStateEntry.self,
        ]
    }
}

/// The migration plan for the persistent store.
///
/// **No custom stages.** Every schema change currently planned is a compatible additive change —
/// optional properties on existing models, or no change at all (the ad-hoc binding reuses the
/// existing orphan `SongSource`). SwiftData performs lightweight migration for those automatically,
/// so a custom `MigrationStage` would be cost without benefit. A stage is added here only when a
/// non-additive change (removing or renaming a property, or changing one's meaning) is actually
/// required — and such a change is a deliberate, recorded decision, not a side effect.
public enum CisumMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CisumSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
