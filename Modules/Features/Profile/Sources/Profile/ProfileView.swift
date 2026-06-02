//
//  ProfileView.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import Aesthetics
import Authentication
import ProviderSDK
import SwiftUI
import Utilities
import YouTubeSDK
#if canImport(SpotifySDK)
import Plugins
import SpotifySDK
#endif

public struct ProfileView: View {
    public init() {}

    @Environment(\.youtube) private var youtube
    @Environment(\.playerViewModel) private var playerViewModel
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
        ZStack {
            Color.cisumBg

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileHeader

                    cisumAccountCard

                    linkedAccountsSection

                    profileStatusCard
                    
                    supportSection

                    Text(
                        "This profile screen is intentionally lightweight for now and will be expanded in a later pass."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaPadding(.top, 80)
            .contentMargins(.bottom, 140)
        }
        .background(Color.cisumBg)
        .ignoresSafeArea()
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
                            // Flow may have expired or not been completed yet
                        }
                    }
                }
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profile")
                .font(.largeTitle.weight(.semibold))
            Text("Connect your Google account for better personalized search and recommendations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - cisum Account Card

    private var cisumAccountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: authService.isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(authService.isAuthenticated ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(authService.user?.username ?? "guest")")
                        .font(.headline)
                    if authService.isAuthenticated {
                        Text(authService.user?.emailAddresses.first?.emailAddress ?? "Signed In")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Using as Guest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if authService.isAuthenticated {
                    Text("Connected")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                } else {
                    Text("Guest")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()

            VStack(spacing: 12) {
                if authService.isAuthenticated {
                    if let fullName = authService.user?.fullName, !fullName.isEmpty {
                        HStack {
                            Text("Name")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(fullName)
                                .font(.subheadline)
                        }
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
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSigningOutcisum)
                } else {
                    VStack(spacing: 12) {
                        Text("Sign in to connect Last.fm, sync listening data, and link Spotify")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            router.navigate(to: .login)
                        } label: {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Linked Accounts

    private var isAppleConnected: Bool {
        authService.user?.verifiedExternalAccounts.contains(where: { $0.provider.lowercased().contains("apple") }) == true
    }

    private var isGoogleConnected: Bool {
        authService.user?.verifiedExternalAccounts.contains(where: { $0.provider.lowercased().contains("google") }) == true
    }

    private var linkedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Linked Accounts")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            Divider()

            VStack(spacing: 16) {
                if authService.isAuthenticated {
                    // Apple
                    HStack {
                        Image(systemName: "applelogo")
                            .font(.title3)
                            .frame(width: 24)
                        Text("Apple")
                        Spacer()
                        if isAppleConnected {
                            Text("Connected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task {
                                    isConnectingApple = true
                                    _ = await authService.connectAppleAccount()
                                    isConnectingApple = false
                                }
                            } label: {
                                if isConnectingApple {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Connect")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isConnectingApple)
                        }
                    }

                    Divider()

                    // Google
                    HStack {
                        Image("googlelogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .frame(width: 24)
                        
                        Text("Google")
                        Spacer()
                        if isGoogleConnected {
                            Text("Connected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task {
                                    isConnectingGoogle = true
                                    _ = await authService.connectGoogleAccount()
                                    isConnectingGoogle = false
                                }
                            } label: {
                                if isConnectingGoogle {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Connect")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isConnectingGoogle)
                        }
                    }
                    
                    Divider()
                }
                
                // YouTube
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube")
                        if hasOAuthSession {
                            Text("Connected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if hasOAuthSession {
                        Button(role: .destructive) {
                            Task {
                                await YouTubeOAuthClient.logout()
                                refreshSessionState()
                            }
                        } label: {
                            Text("Disconnect")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            router.navigate(to: .youtubeLogin)
                        } label: {
                            Text("Connect")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Divider()
                
                // Spotify
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spotify")
                            if spotifyCoordinator.hasSession {
                                Text(spotifyCoordinator.accountDescriptor)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if spotifyCoordinator.hasSession {
                            Button(role: .destructive) {
                                Task {
                                    isSigningOutSpotify = true
                                    await spotifyCoordinator.signOut()
                                    isSigningOutSpotify = false
                                }
                            } label: {
                                if isSigningOutSpotify {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Disconnect")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSigningOutSpotify)
                        } else {
                            #if os(iOS) && canImport(SpotifySDK)
                            Button {
                                router.navigate(to: .spotifyLogin)
                            } label: {
                                Text("Connect")
                            }
                            .buttonStyle(.bordered)
                            .disabled(spotifyCoordinator.isRestoringSession)
                            #else
                            Text("Unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #endif
                        }
                    }
                    
                    #if os(iOS) && canImport(SpotifySDK)
                    if !spotifyCoordinator.hasSession {
                        Toggle(
                            "Use Anonymous Fallback",
                            isOn: Bindable(streamingProviderSettings).spotifyPreferAnonymousFallback
                        )
                        .font(.subheadline)
                    }
                    #endif
                }
                
                Divider()
                
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
//                                                Utilities.Logger.log("Starting LastFM connection flow...")
//                                                let flow = try await scrobbler.startConnection()
//                                                pendingFlowId = flow.flowId
//                                                Utilities.Logger.log("Got flow ID: \(flow.flowId), URL: \(flow.authorizeUrl)")
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
                
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var profileStatusCard: some View {
        HStack(spacing: 12) {
            Image(
                systemName: hasOAuthSession
                    ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
            )
            .font(.title2)
            .foregroundStyle(hasOAuthSession ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasOAuthSession ? "Signed In" : "Not Signed In")
                    .font(.headline)
                Text(
                    hasOAuthSession
                        ? "OAuth session active." : "Sign in to improve search relevance."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support & Diagnostics")
                .font(.headline)
                .padding(.bottom, -8)

            ShareLink(
                item: Logger.getLogFileURL(),
                subject: Text("App Diagnostics"),
                message: Text("Here are the logs from my session:")
            ) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share App Logs")
                            .foregroundStyle(.primary)
                        Text("Send crash and error logs for debugging")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.cisumSurface.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                )
            }
        }
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
            // Unauthenticated or network error
        }
    }
}

#if DEBUG
#Preview {
    ProfileView()
}
#endif
