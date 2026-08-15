//
//  NowPlayingArtwork.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import Models
import SwiftUI

/// The square stage above the song info: artwork, lyrics, or the queue.
///
/// In the default theme the `.artwork` case draws `Color.clear` on purpose. The artwork *is* the
/// vinyl behind this view, and the clear square reserves exactly the footprint lyrics and queue
/// occupy so switching between the three never shifts the layout. Other themes draw a real image
/// here instead.
///
/// `size` and `artworkURL` used to be stored and were never read by `body` — the view sizes itself
/// from `GeometryReader` and the default theme draws no image. They were also part of the
/// synthesised `Equatable`, so the view re-diffed on values that could not change its output.
struct NowPlayingArtwork: View, Equatable {
    let mode: NowPlayingMode

    var body: some View {
        GeometryReader { geometry in
            switch mode {
            case .queue:
                NowPlayingQueueView()
                    .frame(width: geometry.size.width, height: geometry.size.width)
            case .lyrics:
                LyricsView()
                    .frame(width: geometry.size.width, height: geometry.size.width)
            case .artwork:
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 15)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: mode)
    }
}
#endif
