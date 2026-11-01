//
//  ActiveStreamLabel.swift
//  Player
//
//  One small line naming the stream playback is actually using.
//

import PlaybackCore
import SwiftUI

/// Which source is serving the active stream, and what is known about it.
///
/// Reads `PlayerViewModel.activeStreamState`, which is set from the resolved candidate
/// `PlaybackEngine` was handed. It therefore names what is **playing** — including a fallback that
/// replaced the ranked first choice — and never the track that was requested, the canonical song,
/// or a candidate that failed to load.
///
/// Deliberately one caption line: this is a developer-facing diagnostic for watching candidate
/// ranking and fallback work, not a playback dashboard. Full detail is in Settings → Diagnostics,
/// and on macOS the same rows are available as a tooltip.
///
/// Renders nothing when there is no active stream, so stopping playback leaves the surface clean.
struct ActiveStreamLabel: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    private var state: ActiveStreamState {
        playerViewModel.activeStreamState
    }

    var body: some View {
        summary
            .modifier(ActiveStreamTooltip(rows: ActiveStreamDiagnostic.rows(state)))
    }

    @ViewBuilder
    private var summary: some View {
        if let text = ActiveStreamDiagnostic.summary(state) {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(text)
        }
    }

    private var foreground: Color {
        #if os(iOS)
        // The iOS now-playing view sits on artwork, so it uses the same white-on-artwork
        // treatment as the artist line above it, one step further back.
        .white.opacity(0.6)
        #else
        .secondary
        #endif
    }
}

/// macOS shows hover help; iOS has no tooltip, so it simply renders the label.
private struct ActiveStreamTooltip: ViewModifier {
    let rows: [ActiveStreamDiagnosticRow]

    func body(content: Content) -> some View {
        #if os(macOS)
        content.help(rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n"))
        #else
        content
        #endif
    }
}
