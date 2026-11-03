//
//  PaletteScrollView.swift
//  Aesthetics
//
//  The shell of every detail page (artist, album, playlist): the artwork as a hero that stays
//  put while the page scrolls over it, on the artwork's own colour.
//

import SwiftUI

/// A detail page whose hero stays pinned under the content and stretches when pulled down.
///
/// - The hero holds still as the page scrolls, and the content slides up over it, the way
///   Spotify's and Apple Music's artist pages do. It dims as it is covered.
/// - Pulled past the top, it grows from its bottom edge, so it never shows a gap above it.
/// - The page is painted in `palette.background`, and the same colour is declared as the
///   legibility background, so every `legibleForeground` text is drawn in the palette's title
///   and song colours, each checked for contrast against what is actually behind it.
public struct PaletteScrollView<Hero: View, Content: View>: View {
    let palette: ImageColorPalette?
    let heroHeight: CGFloat
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        palette: ImageColorPalette?,
        heroHeight: CGFloat,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.heroHeight = heroHeight
        self.hero = hero()
        self.content = content()
    }

    private var background: Color {
        palette?.background ?? .cisumBg
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .clipped()
                    .visualEffect { [heroHeight, reduceMotion] view, proxy in
                        let minY = proxy.frame(in: .scrollView).minY
                        // Pulled down: grow from the bottom edge, which keeps the top at the top.
                        let stretch = reduceMotion ? 1 : 1 + max(minY, 0) / heroHeight
                        // Scrolled up: move back down by as much as it scrolled, so it stays put.
                        let hold = min(minY, 0)
                        let covered = min(max(-minY / heroHeight, 0), 1)
                        return view
                            .scaleEffect(stretch, anchor: .bottom)
                            .offset(y: -hold)
                            .opacity(1 - covered * 0.7)
                    }

                // Later in the stack draws above, so the content covers the held hero. Opaque in
                // the page colour; the hero's own bottom fade meets it without a seam.
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background)
                    // A short fade above the content's top edge, so it meets the hero softly
                    // as it slides over it rather than as a hard line.
                    .background(alignment: .top) {
                        LinearGradient(colors: [background.opacity(0), background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                            .offset(y: -48)
                            .allowsHitTesting(false)
                    }
            }
        }
        .contentMargins(.bottom, 140, for: .scrollContent)
        .background(background.ignoresSafeArea())
        .legibilityBackground(background)
        .environment(\.legibilityPalette, palette)
        .animation(.easeOut(duration: 0.35), value: palette)
        #if os(iOS)
        // The hero runs up under the status bar. macOS hosts this in a split view's detail
        // column, which handles its own insets.
        .ignoresSafeArea(edges: .top)
        #endif
    }
}
