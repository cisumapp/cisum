import SwiftUI

#if canImport(TidalKit)
import TidalKit
#endif

struct SettingsView: View {
    @Environment(PrefetchSettings.self) private var settings
    @Environment(NetworkPathMonitor.self) private var networkMonitor
    @Environment(StreamingProviderSettings.self) private var streamingProviderSettings

    @State private var snapshot = PlaybackMetricsStore.Snapshot(
        cacheHitRate: 0,
        avgResolveMs: 0,
        avgTapToPlayMs: 0,
        resolveSampleCount: 0,
        tapToPlaySampleCount: 0
    )

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Form {
            Section("Prefetch") {
                Toggle("Adaptive Prefetch", isOn: Bindable(settings).adaptivePrefetchEnabled)

                Picker("Mode", selection: Bindable(settings).prefetchModeOverride) {
                    ForEach(PrefetchModeOverride.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                HStack {
                    Text("Wi-Fi Prefetch Count")
                    Spacer()
                    Text("\(settings.wifiPrefetchCount)")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.wifiPrefetchCount) },
                        set: { settings.wifiPrefetchCount = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )

                HStack {
                    Text("Cellular Prefetch Count")
                    Spacer()
                    Text("\(settings.cellularPrefetchCount)")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.cellularPrefetchCount) },
                        set: { settings.cellularPrefetchCount = Int($0.rounded()) }
                    ),
                    in: 1...5,
                    step: 1
                )

                Toggle("Suggestion Preload Pipeline", isOn: Bindable(settings).suggestionPipelineEnabled)
            }

            Section("Network") {
                LabeledContent("Profile", value: networkMonitor.profileName)
                LabeledContent("Interface", value: networkMonitor.interface.rawValue)
                LabeledContent("Expensive", value: networkMonitor.isExpensive ? "Yes" : "No")
                LabeledContent("Constrained", value: networkMonitor.isConstrained ? "Yes" : "No")
            }

            Section("Streaming Providers") {
                TextField("Spotify Client ID", text: Bindable(streamingProviderSettings).spotifyClientID)

                SecureField("Spotify Client Secret", text: Bindable(streamingProviderSettings).spotifyClientSecret)

                Toggle("Prefer Anonymous Spotify Fallback", isOn: Bindable(streamingProviderSettings).spotifyPreferAnonymousFallback)

                LabeledContent("Spotify Mode", value: streamingProviderSettings.spotifyModeLabel)

#if canImport(TidalKit)
                Picker("Tidal Preferred Quality", selection: Bindable(streamingProviderSettings).tidalPreferredQualityRawValue) {
                    ForEach(MonochromeAudioQuality.descending, id: \.rawValue) { quality in
                        Text(quality.label)
                            .tag(quality.rawValue)
                    }
                }
#else
                LabeledContent("Tidal Preferred Quality", value: streamingProviderSettings.tidalPreferredQualityLabel)
#endif

                Button("Clear Spotify Credentials", role: .destructive) {
                    streamingProviderSettings.clearSpotifyCredentials()
                }
            }

            Section("Diagnostics") {
                Toggle("Enable Metrics", isOn: Bindable(settings).metricsEnabled)
                LabeledContent("Cache Hit %", value: String(format: "%.1f%%", snapshot.cacheHitRate * 100))
                LabeledContent("Avg Resolve", value: String(format: "%.0f ms", snapshot.avgResolveMs))
                LabeledContent("Avg Tap-to-Play", value: String(format: "%.0f ms", snapshot.avgTapToPlayMs))
                LabeledContent("Resolve Samples", value: "\(snapshot.resolveSampleCount)")
                LabeledContent("Tap-to-Play Samples", value: "\(snapshot.tapToPlaySampleCount)")

                Button("Refresh Metrics") {
                    Task { await refreshMetrics() }
                }
                Button("Reset Metrics", role: .destructive) {
                    Task {
                        await PlaybackMetricsStore.shared.reset()
                        await refreshMetrics()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 580)
        .task {
            await refreshMetrics()
        }
        .enableInjection()
    }

    private func refreshMetrics() async {
        snapshot = await PlaybackMetricsStore.shared.snapshot()
    }
}

#Preview {
    SettingsView()
        .injectPreviewSettingsDependencies()
}
