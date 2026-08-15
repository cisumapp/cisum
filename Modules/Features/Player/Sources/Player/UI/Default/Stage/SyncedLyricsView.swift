//
//  SyncedLyricsView.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import Models
import SwiftUI

struct SyncedLyricsView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(playerViewModel.syncedLyricsLines.indices, id: \.self) { index in
                        let line = playerViewModel.syncedLyricsLines[index]
                        let active = isLineActive(line)
                        LyricLineView(
                            line: line,
                            isActive: active,
                            distance: distanceToActiveLine(index)
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 180)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onChange(of: playerViewModel.currentSyncedLyricIndex) { _, newValue in
                if let index = newValue, playerViewModel.syncedLyricsLines.indices.contains(index) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
                        proxy.scrollTo(playerViewModel.syncedLyricsLines[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func isLineActive(_ line: TimedLyricLine) -> Bool {
        guard let index = playerViewModel.currentSyncedLyricIndex else { return false }
        return playerViewModel.syncedLyricsLines[index].id == line.id
    }

    private func distanceToActiveLine(_ index: Int) -> Int {
        guard let currentIndex = playerViewModel.currentSyncedLyricIndex else { return index }
        return abs(index - currentIndex)
    }
}

struct LyricLineView: View {
    let line: TimedLyricLine
    let isActive: Bool
    let distance: Int
    @Environment(PlayerViewModel.self) private var playerViewModel
    /// The playback clock. Only the active line reads it (see the guard in `body`), so a tick
    /// redraws that one line rather than every line in the `ForEach`.
    @Environment(ProgressState.self) private var progress

    var body: some View {
        Group {
            // ponytail: read currentTime only when active — keeps the per-tick
            // re-render scoped to this one line instead of the whole ForEach.
            if isActive, let syllables = line.syllables, !syllables.isEmpty {
                syllablesText(currentTime: progress.currentTime)
            } else {
                Text(line.text)
                    .foregroundStyle(.primary.opacity(isActive ? 1.0 : opacityForDistance))
            }
        }
        .font(.system(size: 34, weight: .heavy, design: .rounded))
        .blur(radius: blurForDistance)
        .scaleEffect(scaleForDistance, anchor: .leading)
        .shadow(color: isActive ? .primary.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            playerViewModel.seek(to: line.timestamp)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isActive)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: distance)
    }

    private func syllablesText(currentTime: TimeInterval) -> Text {
        guard let syllables = line.syllables else { return Text(line.text) }

        var combinedText = Text("")
        for (index, syllable) in syllables.enumerated() {
            let isSyllableActive = currentTime >= syllable.timestamp
            let color = isSyllableActive ? Color.primary : Color.primary.opacity(0.3)

            var sylText = Text(syllable.text).foregroundStyle(color)
            if !syllable.isPartOfWord, index < syllables.count - 1 {
                sylText = sylText + Text(" ")
            }
            combinedText = combinedText + sylText
        }
        return combinedText
    }

    private var opacityForDistance: Double {
        switch distance {
        case 0: 1.0
        case 1: 0.5
        case 2: 0.25
        default: 0.15
        }
    }

    private var blurForDistance: CGFloat {
        switch distance {
        case 0: 0
        case 1: 1.5
        case 2: 3.0
        default: 4.5
        }
    }

    private var scaleForDistance: CGFloat {
        switch distance {
        case 0: 1.0
        case 1: 0.95
        case 2: 0.9
        default: 0.85
        }
    }
}
#endif
