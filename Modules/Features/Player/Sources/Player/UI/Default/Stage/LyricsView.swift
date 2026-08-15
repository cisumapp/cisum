//
//  LyricsView.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    var body: some View {
        ZStack {
            switch playerViewModel.lyricsState {
            case .idle:
                Color.clear
            case .loading:
                ProgressView()
                    .tint(.primary)
                    .scaleEffect(1.5)
            case .synced:
                SyncedLyricsView()
            case .plain:
                PlainLyricsView()
            case let .unavailable(message):
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble.rtl.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.primary.opacity(0.15))

                    Text(message)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            }
        }
    }
}
#endif
