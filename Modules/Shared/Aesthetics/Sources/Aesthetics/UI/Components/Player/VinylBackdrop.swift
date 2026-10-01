//
//  VinylBackdrop.swift
//  Aesthetics
//
//  The record behind everything else. Same platter, same spin physics, no artwork in the
//  label — a blank disc the content and the player bar float over.
//

import SwiftUI

public struct VinylBackdrop: View {
    /// Whether the platter is turning.
    let isPlaying: Bool

    /// Tints the wash behind the disc so the backdrop carries the current track's colour
    /// rather than being a flat grey.
    let accentColor: Color

    /// Diameter of the disc. The backdrop is usually oversized on purpose — it should read
    /// as a record filling the frame, cropped by its edges, not as an object floating in it.
    let diameter: CGFloat

    public init(
        isPlaying: Bool,
        accentColor: Color = .cisumAccent,
        diameter: CGFloat = 1400
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.diameter = diameter
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(diameter, max(geo.size.width, geo.size.height) * 1.4)

            ZStack {
                wash

                // Only the disc is inside the TimelineView. The wash and the frame around it
                // are static, so re-evaluating them 60-120×/s would be pure waste.
                TimelineView(.animation) { timeline in
                    disc(rotation: spin.rotation(at: timeline.date), side: side)
                }
                // Park the spindle well below the band. Centring the disc inside the strip
                // would show its bullseye; pushing its centre down leaves only the wide
                // upper arc sweeping through, which is how a record reads from above.
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height + side * 0.32
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear { spin.syncPlaybackState(at: .now, isPlaying: isPlaying) }
        .onChange(of: isPlaying) { _, playing in
            spin.syncPlaybackState(at: .now, isPlaying: playing)
        }
    }

    @State private var spin = VinylSpin()

    private func disc(rotation: Double, side: CGFloat) -> some View {
        VinylDisk(size: side, rotation: rotation, grooveOpacity: 0.95) {
            // The label area is deliberately empty — this is the "no art" disc. A faint
            // radial tint keeps the spindle from reading as a hole punched in the record.
            Color.black.opacity(0.85)
        }
    }

    /// Radial falloff from the accent colour, so the disc sits in light rather than being a
    /// hard-edged circle pasted over the background.
    private var wash: some View {
        RadialGradient(
            colors: [
                accentColor.opacity(0.42),
                accentColor.opacity(0.20),
                .clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: 700
        )
    }
}
