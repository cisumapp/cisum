//
//  DiscordModel.swift
//  cisum
//
//  Created by Aarav Gupta on 01/10/26.
//

import Combine
import SwiftUI
import Player
import Models

@MainActor
final class DiscordModel: ObservableObject {
    @Published var status = "Not started"
    @Published var friends = 0

    private let bridge = DiscordBridge(appId: 1555145256322867270) // your App ID
    private let tokens = DiscordTokenStore()
    private var timer: Timer?
    
    // Stored properties (add alongside bridge / tokenStore):
    private weak var player: PlayerViewModel?
    private var isReady = false

    /// Connects a player so its now-playing state drives rich presence.
    ///
    /// Call once from the composition root after the player exists. Weak so the app owns the
    /// player's lifetime, not Discord.
    func attach(to player: PlayerViewModel) {
        self.player = player
        player.onNowPlayingChange = { [weak self] in
            self?.syncPresence()
        }
        syncPresence()   // reflect whatever is already playing
    }

    /// Pushes the current track to Discord, or clears presence when nothing is playing.
    private func syncPresence() {
        guard isReady, let player else { return }

        if player.transport.isPlaying, player.nowPlaying.ref != nil {
            bridge.updatePresence(
                withDetails: player.nowPlaying.title,
                state: player.nowPlaying.artist
            )
        } else {
            bridge.clearPresence()
        }
    }

    func start() {
        bridge.onStatus = { [weak self] status in
            guard let self else { return }
            self.status = status
            let ready = status == "Ready"
            self.isReady = ready
            if ready { self.syncPresence() }
        }
        bridge.onFriendsCount = { [weak self] in self?.friends = Int($0) }
        bridge.onTokens = { [weak self] access, refresh, expiresIn in
            self?.tokens.save(access: access, refresh: refresh, expiresIn: Int(expiresIn))
        }
        bridge.onTokenNeedsRefresh = { [weak self] in
            guard let self, let refresh = self.tokens.refreshToken else { return }
            self.bridge.refresh(withRefreshToken: refresh)
        }

        // Silent reconnect when possible; browser OAuth only as a last resort.
        if let access = tokens.accessToken, !tokens.isExpired {
            bridge.connect(withAccessToken: access)
        } else if let refresh = tokens.refreshToken {
            bridge.refresh(withRefreshToken: refresh)
        } else {
            bridge.connect(withAccessToken: nil)
        }

        // 10 Hz is plenty to pump the SDK's callbacks on a desktop app.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            self?.bridge.runCallbacks()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
