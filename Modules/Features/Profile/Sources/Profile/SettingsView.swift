import Authentication
import Caching
import Models
import Networking
import Player
import SwiftUI

public struct SettingsView: View {
    public init() {}

    @Environment(PrefetchSettings.self) private var settings
    @Environment(NetworkPathMonitor.self) private var networkMonitor
    @Environment(PlaybackControlSettings.self) private var playbackControlSettings
    #if os(iOS)
    @Environment(PlayerThemeSettings.self) private var playerThemeSettings
    #endif
    @Environment(AuthService.self) private var authService
    /// The stream playback is using right now — the full detail behind the player's compact label.
    @Environment(PlayerViewModel.self) private var player

    @State private var isSigningOut: Bool = false

    public var body: some View {
        Form {
            // One group so every row takes the brand surface, not the system's cold grouped grey.
            Group {
                #if os(iOS)
                // Player theming is an iOS feature — `PlayerThemeSettings` and
                // `PlayerThemeID` do not exist in the macOS Player module yet.
                Section("Player") {
                    Picker("Theme", selection: Bindable(playerThemeSettings).selected) {
                        ForEach(PlayerThemeID.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }

                    Text(playerThemeSettings.selected.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // add slider for managing vinyl speed
                }
                #endif

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
                        in: 1 ... 10,
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
                        in: 1 ... 5,
                        step: 1
                    )

                    Toggle(
                        "Suggestion Preload Pipeline",
                        isOn: Bindable(settings).suggestionPipelineEnabled
                    )
                }

                Section {
                    LabeledContent(
                        "Crossfade",
                        value: playbackControlSettings.crossfadeSeconds == 0
                            ? "Off" : "\(Int(playbackControlSettings.crossfadeSeconds)) s"
                    )
                    Slider(value: Bindable(playbackControlSettings).crossfadeSeconds, in: 0 ... 12, step: 1)
                    NavigationLink("Equalizer") { EqualizerView() }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Tracks always play without a gap. Songs from the same album never crossfade.")
                }

                Section {
                    Toggle("Spatialize Stereo", isOn: Bindable(playbackControlSettings).spatializesStereo)
                } header: {
                    Text("AirPods")
                } footer: {
                    Text("Plays stereo music as spatial audio. Head tracking follows the setting in Control Center.")
                }

                Section {
                    Toggle("Head Gestures", isOn: Bindable(playbackControlSettings).headGesturesEnabled)
                    if playbackControlSettings.headGesturesEnabled {
                        Picker("Double Nod", selection: Bindable(playbackControlSettings).nodAction) {
                            ForEach(HeadGestureAction.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Shake", selection: Bindable(playbackControlSettings).shakeAction) {
                            ForEach(HeadGestureAction.allCases) { Text($0.title).tag($0) }
                        }
                        LabeledContent("Sensitivity", value: "\(Int(playbackControlSettings.headGestureSensitivity))%")
                        Slider(value: Bindable(playbackControlSettings).headGestureSensitivity, in: 50 ... 200, step: 10)
                    }
                } footer: {
                    Text("With AirPods Pro, AirPods (3rd generation or later) or AirPods Max: nod twice or shake your head. Nodding along to music can look like a double nod.")
                }

                Section("Network") {
                    LabeledContent("Profile", value: networkMonitor.profileName)
                    LabeledContent("Interface", value: networkMonitor.interface.rawValue)
                    LabeledContent("Expensive", value: networkMonitor.isExpensive ? "Yes" : "No")
                    LabeledContent("Constrained", value: networkMonitor.isConstrained ? "Yes" : "No")
                }

                #if os(iOS)
                Section("Playback Controls") {
                    Toggle(
                        "Hold Volume Buttons To Skip",
                        isOn: Bindable(playbackControlSettings).volumeButtonHoldSkipEnabled
                    )

                    Text(
                        "Single taps still change system volume. Skip starts only after the activation delay while playback is active."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text(
                        "At exact 0% or 100% while playing, cisum keeps a tiny headroom reserve so hold-to-skip can still latch reliably."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    LabeledContent(
                        "Activation Delay",
                        value: "\(Int(playbackControlSettings.volumeButtonHoldThreshold * 1000)) ms"
                    )
                    Slider(
                        value: Bindable(playbackControlSettings).volumeButtonHoldThreshold,
                        in: 0.6 ... 1.2,
                        step: 0.05
                    )

                    LabeledContent(
                        "Repeat Interval",
                        value:
                        "\(Int(playbackControlSettings.volumeButtonHoldRepeatInterval * 1000)) ms"
                    )
                    Slider(
                        value: Bindable(playbackControlSettings).volumeButtonHoldRepeatInterval,
                        in: 0.35 ... 0.8,
                        step: 0.05
                    )

                    LabeledContent(
                        "Release Timeout",
                        value:
                        "\(Int(playbackControlSettings.volumeButtonHoldReleaseTimeout * 1000)) ms"
                    )
                    Slider(
                        value: Bindable(playbackControlSettings).volumeButtonHoldReleaseTimeout,
                        in: 0.12 ... 0.35,
                        step: 0.01
                    )

                    Toggle(
                        "Lock Volume During Hold",
                        isOn: Bindable(playbackControlSettings).volumeButtonHoldRestoreVolume
                    )
                    Toggle(
                        "Volume Up Skips Forward",
                        isOn: Bindable(playbackControlSettings).volumeButtonHoldUpSkipsForward
                    )
                }
                #endif

                Section("Diagnostics") {
                    // The active stream: the resolved candidate playback was handed, including a
                    // fallback that replaced the ranked first choice. Unknown fields say so rather
                    // than showing a default.
                    ForEach(ActiveStreamDiagnostic.rows(player.activeStreamState)) { row in
                        LabeledContent(row.label, value: row.value)
                    }
                }
            }
            .listRowBackground(Color.surfaceRaised)
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .contentMargins(.bottom, 50)
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
