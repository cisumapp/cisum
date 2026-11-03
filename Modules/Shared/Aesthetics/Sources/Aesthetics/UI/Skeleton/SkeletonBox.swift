//
//  SkeletonBox.swift
//  Aesthetics
//
//  A plain placeholder shape for skeleton layouts. No animation of its own — wrap the composed
//  skeleton in `.shimmering()` once so every box sweeps together.
//

import SwiftUI

public struct SkeletonBox: View {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 8) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        // The surface's own ink, faint, so a skeleton reads on any page colour — a fixed grey
        // vanished on pale palettes and glared on dark ones.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.foreground)
            .opacity(0.1)
            .legibleForeground(.primary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        SkeletonBox(cornerRadius: 0).frame(width: 140, height: 140)
        SkeletonBox().frame(width: 90, height: 10)
        SkeletonBox().frame(width: 60, height: 8)
    }
    .padding()
    .shimmering()
    .preferredColorScheme(.dark)
}
