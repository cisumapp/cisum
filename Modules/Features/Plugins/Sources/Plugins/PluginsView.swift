import Player
import Plugins
import ProviderSDK
import SwiftUI
import YouTubeSDK

public struct PluginsView: View {
    public init() {}

    @Environment(StreamingProviderSettings.self) private var streamingProviderSettings
    @Environment(ProviderManifestStore.self) private var manifestStore

    @AppStorage("plugins.provider_sdk_enabled") private var providerSDKEnabled = true
    @AppStorage("plugins.youtube_fallback_enabled") private var youtubeFallbackEnabled = true
    @State private var manifestURLString = ""
    @State private var isImportingManifest = false

    public var body: some View {
        Form {
            Section("Playback Chain") {
                Toggle("Enable ProviderSDK", isOn: $providerSDKEnabled)
                Toggle("Enable YouTube Fallback", isOn: $youtubeFallbackEnabled)

                LabeledContent("Active Providers", value: activeProvidersLabel)

                Text(
                    "ProviderSDK resolves first when enabled. YouTube fallback stays available so playback never ends up with an empty resolver chain."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button("Apply Now") {
                    PluginsLog.info("Applying playback configuration from PluginsView", context: [
                        "provider_sdk_enabled": String(providerSDKEnabled),
                        "youtube_fallback_enabled": String(youtubeFallbackEnabled)
                    ])
                    applyPlaybackConfiguration()
                }
            }

            Section("Streaming Sources") {
                Picker(
                    "Radio Recommendations",
                    selection: Bindable(streamingProviderSettings).recommendationSource
                ) {
                    ForEach(StreamingProviderSettings.RecommendationSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                Toggle(
                    "Prefer Anonymous Spotify Fallback",
                    isOn: Bindable(streamingProviderSettings).spotifyPreferAnonymousFallback
                )

                LabeledContent("Spotify Mode", value: streamingProviderSettings.spotifyModeLabel)
                LabeledContent(
                    "Spotify Credentials",
                    value: streamingProviderSettings.hasSpotifyCredentials ? "Configured" : "Missing"
                )
            }

            Section("Provider Manifests") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Import Samples")
                        .font(.subheadline.weight(.semibold))

                    HStack {
                        ForEach(Self.sampleManifests) { sample in
                            Button(sample.label) {
                                PluginsLog.info("Import bundled manifest button tapped", context: [
                                    "file_name": sample.fileName
                                ])
                                Task { await importBundledManifest(sample.fileName) }
                            }
                            .disabled(isImportingManifest)
                        }
                    }
                }

                TextField("Manifest URL", text: $manifestURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button {
                        PluginsLog.info("Import manifest button tapped", context: [
                            "url": manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                        ])
                        Task { await importManifest() }
                    } label: {
                        HStack {
                            Text("Import Manifest")
                            if isImportingManifest {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImportingManifest)

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share cisum Link", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if !manifestStore.manifests.isEmpty {
                    ForEach(manifestStore.manifests, id: \.id) { manifest in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manifest.name)
                                    .fontWeight(.medium)
                                Text(manifestSummary(for: manifest))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { manifestStore.isEnabled(manifest.id) },
                                set: { enabled in
                                    manifestStore.setEnabled(enabled, for: manifest.id)
                                    applyPlaybackConfiguration()
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await manifestStore.removeProvider(manifest.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    Text("No manifests imported yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = manifestStore.lastStatusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = manifestStore.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Status") {
                LabeledContent("ProviderSDK", value: providerSDKEnabled ? "Enabled" : "Disabled")
                LabeledContent("YouTube Fallback", value: youtubeFallbackEnabled ? "Enabled" : "Disabled")
            }
        }
        .navigationTitle("Plugins")
        .onAppear {
            applyPlaybackConfiguration()
        }
        .onChange(of: providerSDKEnabled) { _, _ in
            applyPlaybackConfiguration()
        }
        .onChange(of: youtubeFallbackEnabled) { _, _ in
            applyPlaybackConfiguration()
        }
    }

    private struct SampleManifest: Identifiable {
        let fileName: String
        let label: String

        var id: String {
            fileName
        }
    }

    private static let sampleManifests: [SampleManifest] = [
        .init(fileName: "tidal", label: "TIDAL"),
        .init(fileName: "qobuz", label: "Qobuz"),
        .init(fileName: "deezer", label: "Deezer"),
        .init(fileName: "kuwo", label: "Kuwo")
    ]

    private var shareURL: URL? {
        guard let url = URL(string: manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return manifestStore.cisumImportURL(for: url)
    }

    private var activeProvidersLabel: String {
        var providers: [String] = []

        if providerSDKEnabled {
            providers.append("ProviderSDK")
        }

        if youtubeFallbackEnabled || providers.isEmpty {
            providers.append("YouTube")
        }

        return providers.joined(separator: " -> ")
    }

    private func manifestSummary(for manifest: ProviderManifest) -> String {
        let sourceDescription: String = switch manifest.source {
        case .local:
            "Local"
        case let .remote(url):
            url.host ?? url.absoluteString
        }

        return "\(manifest.id) · \(sourceDescription)"
    }

    private func importManifest() async {
        guard let url = URL(string: manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            manifestStore.setErrorMessage("Enter a valid manifest URL.")
            PluginsLog.error("Invalid manifest URL entered", context: ["value": manifestURLString])
            return
        }

        isImportingManifest = true
        defer { isImportingManifest = false }

        PluginsLog.info("Importing manifest from URL", context: ["url": url.absoluteString])

        do {
            let manifest = try await manifestStore.importManifest(from: url)
            PluginsLog.info("Manifest import completed", context: [
                "provider_id": manifest.id,
                "provider_name": manifest.name
            ])
        } catch {
            manifestStore.setErrorMessage(error.localizedDescription)
            PluginsLog.error("Manifest import failed", context: [
                "url": url.absoluteString,
                "error": error.localizedDescription
            ])
        }
    }

    private func importBundledManifest(_ fileName: String) async {
        guard let url = bundledManifestURL(named: fileName) else {
            manifestStore.setErrorMessage("Bundled manifest \(fileName).cisum is missing.")
            PluginsLog.error("Bundled manifest missing", context: ["file_name": fileName])
            return
        }

        manifestURLString = url.absoluteString
        isImportingManifest = true
        defer { isImportingManifest = false }

        PluginsLog.info("Importing bundled manifest", context: [
            "file_name": fileName,
            "url": url.absoluteString
        ])

        do {
            let manifest = try await manifestStore.importManifest(from: url)
            PluginsLog.info("Bundled manifest import completed", context: [
                "provider_id": manifest.id,
                "provider_name": manifest.name
            ])
        } catch {
            manifestStore.setErrorMessage(error.localizedDescription)
            PluginsLog.error("Bundled manifest import failed", context: [
                "file_name": fileName,
                "error": error.localizedDescription
            ])
        }
    }

    private func bundledManifestURL(named fileName: String) -> URL? {
        if let url = Bundle.module.url(forResource: fileName, withExtension: "cisum") {
            return url
        }

        return Bundle.module.url(forResource: fileName, withExtension: "cisum", subdirectory: "Manifests")
    }

    private func applyPlaybackConfiguration() {
        PluginsLog.debug("Applying playback configuration", context: [
            "provider_sdk_enabled": String(providerSDKEnabled),
            "youtube_fallback_enabled": String(youtubeFallbackEnabled)
        ])
        Plugins.reconfigurePlaybackURLResolver(
            includeProviderSDK: providerSDKEnabled,
            includeYouTubeFallback: youtubeFallbackEnabled
        )
    }
}

#Preview {
    PluginsView()
        .environment(StreamingProviderSettings.shared)
        .environment(ProviderManifestStore.shared)
}
