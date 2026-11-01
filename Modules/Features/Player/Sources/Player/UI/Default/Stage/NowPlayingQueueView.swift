//
//  NowPlayingQueueView.swift
//  Player
//
//  The queue, laid out after Apple Music's Playing Next: History above, what the user queued,
//  then what Autoplay added — with shuffle, repeat and autoplay as pill toggles.
//

#if os(iOS)
import Kingfisher
import Models
import SwiftUI

struct NowPlayingQueueView: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !player.queueHistory.isEmpty {
                    Section {
                        ForEach(player.queueHistory) { row in
                            QueueRowView(row: row, isPlayed: true)
                                .onTapGesture { player.playQueueEntry(at: row.index) }
                        }
                        .onDelete { remove($0, from: player.queueHistory) }
                    } header: {
                        QueueSectionHeader(title: "History")
                    }
                }

                Section {
                    ForEach(player.queuePlayingNext) { row in
                        QueueRowView(row: row)
                            .onTapGesture { player.playQueueEntry(at: row.index) }
                    }
                    .onMove { move($0, $1, within: player.queuePlayingNext) }
                    .onDelete { remove($0, from: player.queuePlayingNext) }
                } header: {
                    playingNextHeader
                        .id(Self.playingNextID)
                }

                if player.isAutoplayEnabled, !player.queueAutoplay.isEmpty {
                    Section {
                        ForEach(player.queueAutoplay) { row in
                            QueueRowView(row: row)
                                .onTapGesture { player.playQueueEntry(at: row.index) }
                        }
                        .onMove { move($0, $1, within: player.queueAutoplay) }
                        .onDelete { remove($0, from: player.queueAutoplay) }
                    } header: {
                        QueueSectionHeader(title: "Autoplay", subtitle: "Mixed from this station and your music")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // History sits above, as in Apple Music: open on what is coming, scroll up for the past.
            .onAppear { proxy.scrollTo(Self.playingNextID, anchor: .top) }
        }
    }

    private static let playingNextID = "playing-next"

    private var playingNextHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                if player.queuePlayingNext.isEmpty, player.isAutoplayEnabled {
                    Text("Autoplay continues below")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            QueueToggle(symbol: "shuffle", isOn: player.playbackMode == .shuffle, label: "Shuffle") {
                player.toggleShuffle()
            }
            QueueToggle(
                symbol: player.playbackMode == .repeatOne ? "repeat.1" : "repeat",
                isOn: player.playbackMode == .repeatAll || player.playbackMode == .repeatOne,
                label: "Repeat"
            ) {
                player.cycleRepeat()
            }
            QueueToggle(symbol: "infinity", isOn: player.isAutoplayEnabled, label: "Autoplay") {
                player.setAutoplay(!player.isAutoplayEnabled)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Editing

    /// `List.onMove` reports offsets within the section; the queue wants whole-queue indices.
    private func move(_ source: IndexSet, _ destination: Int, within rows: [PlayerViewModel.QueueRow]) {
        guard let from = source.first.map({ rows[$0].index }), let last = rows.last else { return }
        let to = destination < rows.count ? rows[destination].index : last.index + 1
        player.moveQueueEntry(from: from, to: to)
    }

    private func remove(_ offsets: IndexSet, from rows: [PlayerViewModel.QueueRow]) {
        // Highest first, so each removal leaves the remaining indices valid.
        for index in offsets.map({ rows[$0].index }).sorted(by: >) {
            player.removeQueueEntry(at: index)
        }
    }
}

// MARK: - Pieces

private struct QueueRowView: View {
    let row: PlayerViewModel.QueueRow
    var isPlayed = false

    var body: some View {
        HStack(spacing: 12) {
            KFImage(row.artworkURL)
                .placeholder { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.12)) }
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if !isPlayed {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
        .opacity(isPlayed ? 0.5 : 1)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isPlayed ? "Plays again" : "Plays this track")
    }
}

private struct QueueSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// A pill toggle, filled when on — the shuffle / repeat / autoplay buttons in Apple Music's queue.
private struct QueueToggle: View {
    let symbol: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 30)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
#endif
