//
//  ProfileView.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import Aesthetics
import Authentication
import Models
import ProviderSDK
import SwiftUI
import UniformTypeIdentifiers
import Utilities
import YouTubeSDK
#if canImport(SpotifySDK)
import SpotifySDK
#endif

public struct ProfileView: View {
    public init() {}

    private let youtube = YouTube.shared
    @Environment(AuthService.self) private var authService
    @Environment(SpotifySessionCoordinator.self) private var spotifyCoordinator
    @Environment(AnalyticsService.self) private var analyticsService
    @Environment(\.router) private var router

    @Environment(StreamingProviderSettings.self) private var streamingProviderSettings
    @Environment(LastFMSettings.self) private var lastFMSettings
    @Environment(\.lastFMScrobbler) private var lastFMScrobbler
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasOAuthSession: Bool = false
    @State private var isSigningOutSpotify: Bool = false
    @State private var isSigningOutcisum: Bool = false
    @State private var isConnectingApple: Bool = false
    @State private var isConnectingGoogle: Bool = false
    @State private var isConnectingLastFM: Bool = false
    @State private var pendingFlowId: String?

    public var body: some View {
        List {
            // One group so every row takes the brand surface, not the system's cold grouped grey.
            Group {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if authService.isAuthenticated {
                    accountSection
                }

                servicesSection

                Section {
                    ShareLink(item: DiagnosticsLog(), preview: SharePreview("cisum diagnostics")) {
                        serviceRow("Share diagnostics", status: "Recent app logs, for bug reports") {
                            iconTile("doc.text.magnifyingglass", tint: .gray)
                        } action: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listRowBackground(Color.surfaceRaised)
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceBackground.ignoresSafeArea())
        .contentMargins(.bottom, 140, for: .scrollContent)
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            refreshSessionState()
        }
        .task {
            await refreshLastFMStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await refreshLastFMStatus()

                    if let flowId = pendingFlowId {
                        do {
                            if let scrobbler = lastFMScrobbler {
                                let result = try await scrobbler.completeConnection(flowId: flowId)
                                if result.connected {
                                    lastFMSettings.updateConnectionStatus(connected: true, username: result.lastfmUsername)
                                    pendingFlowId = nil
                                }
                            }
                        } catch {
                            PerfLog.error("Profile: Last.fm completeConnection failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    /// The one large thing on the page: who this is.
    private var header: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                Text(authService.isAuthenticated
                    ? authService.user?.emailAddresses.first?.emailAddress ?? "Signed in"
                    : "Sign in to sync your library and link your services")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !authService.isAuthenticated {
                Button("Sign In") { router.navigate(to: .login) }
                    .buttonStyle(.cisumProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var displayName: String {
        guard authService.isAuthenticated else { return "Guest" }
        if let fullName = authService.user?.fullName, !fullName.isEmpty {
            return fullName
        }
        return authService.user?.username.map { "@\($0)" } ?? "Signed in"
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = authService.user, user.hasImage, let url = URL(string: user.imageUrl) {
            ArtworkImage(url: url, size: 96)
                .clipShape(.circle)
        } else {
            Circle()
                .fill(.surfaceRaised)
                .overlay {
                    if authService.isAuthenticated {
                        Text(initials)
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var initials: String {
        let name = authService.user?.fullName ?? authService.user?.username ?? ""
        return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if let fullName = authService.user?.fullName, !fullName.isEmpty {
                LabeledContent("Name", value: fullName)
            }
            if let username = authService.user?.username {
                LabeledContent("Username", value: "@\(username)")
            }

            Button(role: .destructive) {
                Task {
                    isSigningOutcisum = true
                    await authService.signOut()
                    analyticsService.reset()
                    isSigningOutcisum = false
                }
            } label: {
                HStack {
                    Text("Sign Out")
                    if isSigningOutcisum {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSigningOutcisum)
        }
    }

    // MARK: - Connected services

    private var isAppleConnected: Bool {
        authService.user?.verifiedExternalAccounts.contains(where: { $0.provider.lowercased().contains("apple") }) == true
    }

    private var isGoogleConnected: Bool {
        authService.user?.verifiedExternalAccounts.contains(where: { $0.provider.lowercased().contains("google") }) == true
    }

    private var servicesSection: some View {
        Section {
            if authService.isAuthenticated {
                serviceRow("Apple", status: isAppleConnected ? "Connected" : nil) {
                    iconTile("applelogo", tint: .black)
                } action: {
                    if isAppleConnected {
                        connectedMark
                    } else {
                        connectButton(isBusy: isConnectingApple) {
                            isConnectingApple = true
                            if await authService.connectAppleAccount() == false {
                                PerfLog.error("Profile: Apple account connect failed")
                            }
                            isConnectingApple = false
                        }
                    }
                }

                serviceRow("Google", status: isGoogleConnected ? "Connected" : nil) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white)
                        .overlay {
                            Image("googlelogo")
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        }
                } action: {
                    if isGoogleConnected {
                        connectedMark
                    } else {
                        connectButton(isBusy: isConnectingGoogle) {
                            isConnectingGoogle = true
                            if await authService.connectGoogleAccount() == false {
                                PerfLog.error("Profile: Google account connect failed")
                            }
                            isConnectingGoogle = false
                        }
                    }
                }
            }

            serviceRow("YouTube", status: hasOAuthSession ? "Connected" : "Personalised search") {
                iconTile("play.rectangle.fill", tint: .red)
            } action: {
                if hasOAuthSession {
                    disconnectButton(isBusy: false) {
                        YouTubeOAuthClient.logout()
                        refreshSessionState()
                    }
                } else {
                    connectButton(isBusy: false) { router.navigate(to: .youtubeLogin) }
                }
            }

            serviceRow("Spotify", status: spotifyCoordinator.hasSession ? spotifyCoordinator.accountDescriptor : "Your playlists and liked songs") {
                iconTile("music.note", tint: .green)
            } action: {
                if spotifyCoordinator.hasSession {
                    disconnectButton(isBusy: isSigningOutSpotify) {
                        isSigningOutSpotify = true
                        await spotifyCoordinator.signOut()
                        isSigningOutSpotify = false
                    }
                } else {
                    #if os(iOS) && canImport(SpotifySDK)
                    connectButton(isBusy: spotifyCoordinator.isRestoringSession) { router.navigate(to: .spotifyLogin) }
                    #else
                    Text("Unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }

            #if os(iOS) && canImport(SpotifySDK)
            Toggle("Anonymous Spotify Mode", isOn: Bindable(streamingProviderSettings).spotifyPreferAnonymousFallback)
            if spotifyCoordinator.hasSession {
                Toggle("Sync Liked Songs", isOn: Bindable(streamingProviderSettings).spotifySyncLikedSongs)
                Toggle("Allow Changes to Spotify", isOn: Bindable(streamingProviderSettings).spotifyAllowWrites)
            }
            #endif

            // Last.fm
//                VStack(spacing: 12) {
//                    HStack {
//                        Image(systemName: "waveform")
//                            .font(.title3)
//                            .foregroundStyle(.red)
//                            .frame(width: 24)
//
//                        VStack(alignment: .leading, spacing: 2) {
//                            Text("Last.fm")
//                            if lastFMSettings.isConnected {
//                                Text(lastFMSettings.lastfmUsername ?? "Connected")
//                                    .font(.caption2)
//                                    .foregroundStyle(.secondary)
//                                    .lineLimit(1)
//                            }
//                        }
//                        Spacer()
//                        if lastFMSettings.isConnected {
//                            Button(role: .destructive) {
//                                Task {
//                                    do {
//                                        try await lastFMScrobbler?.disconnect()
//                                        lastFMSettings.clearConnection()
//                                    } catch { }
//                                }
//                            } label: {
//                                Text("Disconnect")
//                            }
//                            .buttonStyle(.bordered)
//                        } else {
//                            if authService.isAuthenticated {
//                                Button {
//                                    Task {
//                                        isConnectingLastFM = true
//                                        defer { isConnectingLastFM = false }
//                                        do {
//                                            if let scrobbler = lastFMScrobbler {
//                                                PerfLog.info("Starting LastFM connection flow...")
//                                                let flow = try await scrobbler.startConnection()
//                                                pendingFlowId = flow.flowId
//                                                PerfLog.info("Got flow ID: \(flow.flowId), URL: \(flow.authorizeUrl)")
//                                                if let url = URL(string: flow.authorizeUrl) {
//                                                    openURL(url)
//                                                } else {
//                                                    Utilities.Logger.error("Failed to create URL from: \(flow.authorizeUrl)")
//                                                }
//                                            } else {
//                                                Utilities.Logger.error("lastFMScrobbler is nil in Environment!")
//                                            }
//                                        } catch {
//                                            Utilities.Logger.error("Last.fm Connect Error: \(error)")
//                                        }
//                                    }
//                                } label: {
//                                    if isConnectingLastFM {
//                                        ProgressView().controlSize(.small)
//                                    } else {
//                                        Text("Connect")
//                                    }
//                                }
//                                .buttonStyle(.bordered)
//                                .disabled(isConnectingLastFM)
//                            } else {
//                                Text("Sign in to connect")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//
//                    if lastFMSettings.isConnected {
//                        Toggle("Enable Scrobbling", isOn: Bindable(lastFMSettings).enabled)
//                            .font(.subheadline)
//                        Toggle("Save Local Listening History", isOn: Bindable(lastFMSettings).localHistoryEnabled)
//                            .font(.subheadline)
//                    }
//                }
        } header: {
            Text("Connected services")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Signed out, cisum still finds every artist, album and playlist through YouTube Music and Apple's catalogue.")
                if spotifyCoordinator.hasSession {
                    Text("Sync Liked Songs keeps a read-only copy in your library. Allow Changes to Spotify lets cisum like songs, follow artists and edit playlists on your account; it's off by default because Spotify may flag unofficial clients that write.")
                }
            }
        }
    }

    // MARK: - Rows

    private func serviceRow(
        _ title: String,
        status: String?,
        @ViewBuilder icon: () -> some View,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            action()
        }
        .padding(.vertical, 2)
    }

    /// The Settings app's tinted square, so services read as one family.
    private func iconTile(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var connectedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityLabel("Connected")
    }

    private func connectButton(isBusy: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Text("Connect")
            }
        }
        .buttonStyle(.cisumSecondary)
        .controlSize(.small)
        .disabled(isBusy)
    }

    private func disconnectButton(isBusy: Bool, action: @escaping () async -> Void) -> some View {
        Button(role: .destructive) {
            Task { await action() }
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Text("Disconnect")
            }
        }
        .buttonStyle(.cisumSecondary)
        .controlSize(.small)
        .disabled(isBusy)
    }

    private func refreshSessionState() {
        Task {
            let hasToken = await YouTubeOAuthClient().hasValidToken()
            await MainActor.run {
                hasOAuthSession = hasToken
            }
        }
    }

    private func refreshLastFMStatus() async {
        do {
            if let scrobbler = lastFMScrobbler {
                let status = try await scrobbler.checkConnectionStatus()
                lastFMSettings.updateConnectionStatus(connected: status.connected, username: status.lastfmUsername)
            }
        } catch {
            PerfLog.warning("Profile: Last.fm status refresh failed (unauthenticated or network): \(error.localizedDescription)")
        }
    }
}

/// The app's log as a file, written only when the user picks where to share it. It used to be
/// written in `body`: `getLogFileURL()` walks the whole session's log store and writes a file,
/// synchronously on the main thread, on every render — which is what made the page slow to open.
private struct DiagnosticsLog: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            SentTransferredFile(PerfLog.getLogFileURL())
        }
    }
}

#if DEBUG
#Preview {
    ProfileView()
}
#endif
