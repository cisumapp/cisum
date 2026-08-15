//
//  MulticolorGradient.swift
//  Player
//
//  Adapted from AppleMusicStylePlayer by Alexey Vorobyov.
//  https://github.com/f728743/AppleMusicStylePlayer
//
//  MIT License — Copyright (c) 2025 Alexey Vorobyov. The full licence text, required to travel
//  with substantial portions of the Software, is in THIRD_PARTY_LICENSES.md at the repo root.
//

import SwiftUI

struct MulticolorGradient: View, Animatable {
    var points: ColorPoints
    var animationUpdateHandler: (@Sendable (ColorPoints) -> Void)?

    var uniforms: Uniforms {
        Uniforms(params: GradientParams(points: points, bias: 0.05, power: 2.5, noise: 2))
    }

    nonisolated var animatableData: ColorPoints.AnimatableData {
        get {
            points.animatableData
        }
        set {
            let newPoints = ColorPoints(newValue)
            points = newPoints
            let viewCopy = self
            Task { @MainActor in
                viewCopy.animationUpdateHandler?(newPoints)
            }
        }
    }

    var body: some View {
        Rectangle()
            // `.bundle(.module)`, not the default library. ShaderLibrary looks in the main
            // bundle unless told otherwise, and Player is a SwiftPM package whose compiled
            // metallib lives in its own resource bundle — the default lookup finds nothing and
            // the effect silently does not draw, with no compile error.
            .colorEffect(ShaderLibrary.bundle(.module).gradient(.boundingRect, .uniforms(uniforms)))
    }
}

@MainActor
private extension MulticolorGradient {
    mutating func updatePoints(newPoints: ColorPoints) {
        points = newPoints
        animationUpdateHandler?(newPoints)
    }
}

extension Shader.Argument {
    static func uniforms(_ param: Uniforms) -> Shader.Argument {
        var copy = param
        return .data(Data(bytes: &copy, count: MemoryLayout<Uniforms>.stride))
    }
}

#Preview {
    MulticolorGradient(
        points: ColorPoints(
            points: [
                ColorPoint(position: .top, color: .pink),
                ColorPoint(position: .leading, color: .indigo),
                ColorPoint(position: .bottomTrailing, color: .cyan),
            ]
        )
    )
    .ignoresSafeArea()
}
