//
//  ShuffleButton.swift
//  cisum
//

import SwiftUI

struct ShuffleButton: View {
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        Button {
            playerViewModel.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .font(.title3)
                .foregroundStyle(playerViewModel.isShuffled ? Color.accentColor : Color.white)
        }
        .sensoryFeedback(.selection, trigger: playerViewModel.isShuffled)
        .accessibilityLabel("Shuffle")
        .disabled(playerViewModel.currentVideoId == nil)
    }
}
