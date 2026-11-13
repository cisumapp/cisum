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

    /// Width of whatever covers the leading edge (the sidebar). The disc centres on the rest, so
    /// it sits behind the content and moves over when the sidebar folds away.
    let leadingInset: CGFloat

    public init(
        isPlaying: Bool,
        accentColor: Color = .cisumAccent,
        leadingInset: CGFloat = 0
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.leadingInset = leadingInset
    }

    /// The design's record (Figma 86:6263): 1810pt across in a 1280pt window, its rim 12pt below
    /// the top edge, so it fills the window and only its upper arc and grooves show behind the
    /// chrome. It used to be parked below the frame as a band, leaving an arc at the bottom.
    private static let widthRatio: CGFloat = 1810 / 1280
    private static let topInset: CGFloat = 12
    private static let centreBelowBottom: CGFloat = 133

    public var body: some View {
        GeometryReader { geo in
            // The design's proportion, but never so small that the centre comes into view: in the
            // 1280×784 frame it sits 133pt below the bottom edge, and a taller window would
            // otherwise pull the label up into the content.
            let side = max(geo.size.width * Self.widthRatio, (geo.size.height - Self.topInset + Self.centreBelowBottom) * 2)
            let center = CGPoint(
                x: leadingInset + (geo.size.width - leadingInset) / 2,
                y: Self.topInset + side / 2
            )

            ZStack {
                wash
                    .position(center)

                // Only the disc is inside the TimelineView. The wash and the frame around it
                // are static, so re-evaluating them 60-120×/s would be pure waste.
                TimelineView(.animation(minimumInterval: nil, paused: !spin.isTurning)) { timeline in
                    disc(rotation: spin.rotation(at: timeline.date), side: side)
                }
                .position(center)
            }
            #if os(macOS)
            .animation(MacSplitView.sidebarAnimation, value: leadingInset)
            #else
            .animation(.smooth(duration: 0.25), value: leadingInset)
            #endif
        }
        .allowsHitTesting(false)
        .onAppear { spin.syncPlaybackState(at: .now, isPlaying: isPlaying) }
        .onChange(of: isPlaying) { _, playing in
            spin.syncPlaybackState(at: .now, isPlaying: playing)
        }
        .task(id: isPlaying) {
            await spin.settle(isPlaying: isPlaying)
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
