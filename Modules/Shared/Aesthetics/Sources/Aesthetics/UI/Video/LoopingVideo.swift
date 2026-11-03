//
//  LoopingVideo.swift
//  Aesthetics
//
//  A silent, endlessly looping video filling its frame: animated artwork.
//

import AVFoundation
import SwiftUI

/// Plays a local video muted and on a loop, cropped to fill its frame.
public struct LoopingVideo: View {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        LoopingVideoLayer(url: url)
            .id(url)
            .accessibilityHidden(true)
    }
}

/// Owns the player for one URL; a new URL gets a new view (`.id(url)`), so nothing is reused
/// across tracks.
@MainActor
private final class LoopingVideoPlayer {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Never interrupts the music: animated artwork has no sound worth an audio session.
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
}

#if os(iOS)
private struct LoopingVideoLayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context _: Context) -> PlayerView {
        PlayerView(player: LoopingVideoPlayer(url: url))
    }

    func updateUIView(_: PlayerView, context _: Context) {}

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private let owner: LoopingVideoPlayer

        init(player: LoopingVideoPlayer) {
            owner = player
            super.init(frame: .zero)
            let playerLayer = layer as? AVPlayerLayer
            playerLayer?.player = player.player
            playerLayer?.videoGravity = .resizeAspectFill
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }
    }
}
#elseif os(macOS)
private struct LoopingVideoLayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> PlayerView {
        PlayerView(player: LoopingVideoPlayer(url: url))
    }

    func updateNSView(_: PlayerView, context _: Context) {}

    final class PlayerView: NSView {
        private let owner: LoopingVideoPlayer

        init(player: LoopingVideoPlayer) {
            owner = player
            super.init(frame: .zero)
            let layer = AVPlayerLayer(player: player.player)
            layer.videoGravity = .resizeAspectFill
            self.layer = layer
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }
    }
}
#endif
