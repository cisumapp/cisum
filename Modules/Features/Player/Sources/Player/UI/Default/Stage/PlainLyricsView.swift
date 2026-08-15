//
//  PlainLyricsView.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import SwiftUI

struct PlainLyricsView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(playerViewModel.plainLyricsText ?? "")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .multilineTextAlignment(.leading)
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
