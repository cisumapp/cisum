//
//  EqualizerView.swift
//  Player
//

import PlaybackCore
import SwiftUI

/// The equalizer: on/off, a preset, and a slider per band.
public struct EqualizerView: View {
    @Bindable private var settings = EqualizerSettings.shared

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Equalizer", isOn: $settings.isEnabled)
                Picker("Preset", selection: presetBinding) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.name).tag(Optional(preset))
                    }
                    if settings.preset == nil {
                        Text("Custom").tag(EqualizerPreset?.none)
                    }
                }
            }

            Section {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Equalizer.frequencies.indices, id: \.self) { band in
                        bandSlider(band)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .disabled(!settings.isEnabled)
                .opacity(settings.isEnabled ? 1 : 0.4)
            } footer: {
                Text("Applies to every track, through crossfades. HLS streams, used only as a fallback, play unequalized.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Equalizer")
    }

    private var presetBinding: Binding<EqualizerPreset?> {
        Binding(
            get: { settings.preset },
            set: { if let preset = $0 { settings.gains = preset.gains } }
        )
    }

    private func bandSlider(_ band: Int) -> some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.0f", settings.gains[band]))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            // SwiftUI has no vertical slider; a horizontal one turned on its side.
            Slider(value: $settings.gains[band], in: Equalizer.gainRange, step: 1)
                .frame(width: 160)
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 160)
            Text(Self.label(Equalizer.frequencies[band]))
                .font(.caption2)
        }
    }

    private static func label(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }
}
