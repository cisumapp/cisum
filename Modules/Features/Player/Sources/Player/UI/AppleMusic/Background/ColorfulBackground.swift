//
//  ColorfulBackground.swift
//  Player
//
//  Adapted from AppleMusicStylePlayer by Alexey Vorobyov.
//  https://github.com/f728743/AppleMusicStylePlayer
//
//  MIT License — Copyright (c) 2025 Alexey Vorobyov. The full licence text, required to travel
//  with substantial portions of the Software, is in THIRD_PARTY_LICENSES.md at the repo root.
//

import SwiftUI

struct ColorfulBackground: View {
    @State var model = ColorfulBackgroundModel()
    let colors: [Color]

    var body: some View {
        MulticolorGradient(
            points: model.points,
            animationUpdateHandler: { [weak model] newPoints in
                Task { @MainActor in
                    model?.onUpdate(animatedData: newPoints)
                }
            }
        )
        .onAppear {
            model.set(colors)
            model.onAppear()
        }
        .onChange(of: colors) {
            model.set(colors)
        }
    }
}

#Preview {
    ColorfulBackground(colors: [.pink, .indigo, .cyan])
        .ignoresSafeArea()
}
