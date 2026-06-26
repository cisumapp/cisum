//
//  ImportServicesFactory.swift
//  Library
//
//  Builds the [ImportProvider: any ImportService] registry the Download Manager consumes.
//  Lives in Library so it can reach the Spotify session coordinator (Plugins) + both SDKs.
//

import Foundation
import Models         // ImportProvider
import Plugins        // SpotifySessionCoordinator
import YouTubeSDK

#if canImport(SpotifySDK)
import SpotifySDK
#endif

public enum ImportServicesFactory {
    @MainActor
    public static func make(
        youtube: YouTube,
        spotifyCoordinator: SpotifySessionCoordinator
    ) -> [ImportProvider: any ImportService] {
        var services: [ImportProvider: any ImportService] = [:]

        services[.youtube] = YouTubeImportService(youtube: youtube)
        services[.localFile] = LocalFileImportService()

        #if canImport(MusicKit)
        services[.appleMusic] = AppleMusicImportService()
        #endif

        #if canImport(SpotifySDK)
        services[.spotify] = SpotifyImportService(
            sdkProvider: { spotifyCoordinator.sdk ?? spotifyCoordinator.session.map { SpotifySDK(session: $0) } },
            isAuthorized: { await MainActor.run { spotifyCoordinator.isAuthenticated } }
        )
        #endif

        return services
    }
}
