//
//  Shimmer.swift
//  Aesthetics
//
//  A single diagonal light sweep used for skeleton loading placeholders. Apply once on the
//  composed skeleton (not per box) so the sweep stays in sync and masks to all opaque shapes.
//

import SwiftUI

public struct ShimmerModifier: ViewModifier {
    @State private var animating = false

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: animating ? w * 1.4 : -w * 0.9)
                }
                .mask(content) // sweep only shows over the skeleton's opaque shapes
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

public extension View {
    /// Adds an animated shimmer sweep. Put it on the composed skeleton once.
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
