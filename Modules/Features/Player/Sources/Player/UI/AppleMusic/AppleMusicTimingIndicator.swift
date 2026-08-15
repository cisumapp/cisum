//
//  AppleMusicTimingIndicator.swift
//  Player
//
//  Follows TimingIndicator in AppleMusicStylePlayer (MIT, © 2025 Alexey Vorobyov).
//

#if os(iOS)
import Models
import SwiftUI

/// Scrubber plus elapsed and remaining times.
///
/// Reads `ProgressState` directly rather than going through the view model, so the ~30Hz position
/// tick invalidates this view and nothing else in the player. See `PlayerState.swift`.
struct AppleMusicTimingIndicator: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(ProgressState.self) private var progress

    let spacing: CGFloat

    /// Position while the user is dragging. The player's own clock keeps running underneath, so
    /// without this the thumb would fight the finger.
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: spacing) {
            ElasticSlider(
                value: Binding(
                    get: { scrubbing ?? progress.currentTime },
                    set: { scrubbing = $0 }
                ),
                in: 0 ... max(player.duration, 1),
                onEditingChanged: { editing in
                    guard !editing else { return }
                    // Committed once, on release. Seeking on every intermediate value would
                    // re-seek dozens of times per drag, which is audible as stutter.
                    if let target = scrubbing {
                        player.seek(to: target)
                    }
                    scrubbing = nil
                }
            ) {
                EmptyView()
            } trailingLabel: {
                EmptyView()
            }

            times
        }
        .onDisappear { scrubbing = nil }
    }

    private var times: some View {
        HStack {
            Text(label(scrubbing ?? progress.currentTime))
            Spacer()
            Text("-" + label(max(player.duration - (scrubbing ?? progress.currentTime), 0)))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .blendMode(.overlay)
    }

    private func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
