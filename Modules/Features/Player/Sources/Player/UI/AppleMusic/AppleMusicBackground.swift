//
//  AppleMusicBackground.swift
//  Player
//

#if os(iOS)
import Aesthetics
import Models
import SwiftUI

/// The colour wash behind the Apple Music theme.
///
/// Feeds `ColorfulBackground` — the imported Metal gradient — from cisum's existing
/// `ImageColorExtractor` rather than the reference project's own `DominantColors`. Importing a
/// second extractor would have meant carrying two implementations of the same idea, and the app
/// already picks accent colours from artwork elsewhere.
struct AppleMusicBackground: View {
    @Environment(NowPlayingState.self) private var nowPlaying

    let expanded: Bool

    @State private var colors: [Color] = AppleMusicBackground.fallback

    /// Neutral wash used before any artwork has been analysed, and when extraction fails.
    /// Deliberately dark and low-contrast so the transition to real colours is not jarring.
    static let fallback: [Color] = [
        Color(white: 0.18),
        Color(white: 0.10),
        Color(white: 0.22),
    ]

    var body: some View {
        ColorfulBackground(colors: colors)
            // The gradient is bright. Apple Music sits a scrim over it so white text stays legible
            // against light artwork; without this, pale album covers wash the labels out.
            .overlay(Color.black.opacity(expanded ? 0.28 : 0.4))
            .animation(.easeInOut(duration: 0.6), value: colors)
            .ignoresSafeArea()
            // Keyed on the URL so a track change re-extracts and returning to the same track does
            // not. `.task(id:)` also cancels the in-flight fetch when the user skips quickly.
            .task(id: nowPlaying.artworkURL) {
                await loadColors(from: nowPlaying.artworkURL)
            }
    }

    private func loadColors(from url: URL?) async {
        guard let url else {
            colors = Self.fallback
            return
        }

        // Request a small image: colour analysis needs no more than a thumbnail, and this avoids
        // pulling a 544px artwork over the network purely to average it.
        let analysisURL = ImageColorExtractor.paletteURL(from: url)

        guard let (data, _) = try? await URLSession.shared.data(from: analysisURL),
              !Task.isCancelled,
              let palette = await ImageColorExtractor.shared.extractPalette(
                  from: data,
                  cacheKey: url.absoluteString
              )
        else {
            colors = Self.fallback
            return
        }

        // The gradient wants distinct points rather than a designed foreground/background pair,
        // so it takes the three least-related colours the palette exposes.
        colors = [palette.dominant, palette.background, palette.songs]
    }
}
#endif
