//
//  PluginDetailView.swift
//  Plugins
//
//  One plugin: its settings, updates, removal.
//

import SwiftUI

/// Detail screen for an installed plugin.
public struct PluginDetailView: View {
    @Environment(PluginStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let pluginID: String

    @State private var isUpdating = false
    @State private var showRemoveConfirmation = false

    public init(pluginID: String) {
        self.pluginID = pluginID
    }

    private var plugin: InstalledPlugin? {
        store.installed.first { $0.id == pluginID }
    }

    public var body: some View {
        Form {
            if let plugin {
                Section {
                    LabeledContent("Version", value: plugin.version.isEmpty ? "—" : plugin.version)
                    if let author = plugin.author {
                        LabeledContent("Author", value: author)
                    }
                    if let summary = plugin.summary {
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                    }
                }

                if !plugin.labels.isEmpty {
                    Section("Capabilities") {
                        Text(plugin.labels.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Enabled", isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { newValue in
                            Task { await store.setEnabled(newValue, for: plugin.id) }
                        }
                    ))

                    if store.hasUpdate(plugin) {
                        Button {
                            Task {
                                isUpdating = true
                                try? await store.update(plugin.id)
                                isUpdating = false
                            }
                        } label: {
                            HStack {
                                Text("Update")
                                if isUpdating {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isUpdating)
                    }
                }

                Section {
                    Button("Remove Plugin", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                } footer: {
                    // Worth stating plainly: the registry publishes no hashes and no signatures,
                    // and a plugin runs arbitrary JavaScript with network access. `trusted` in the
                    // registry is a curator's opinion, not a verified property.
                    Text("Plugins run code written by third parties. Only install ones you trust.")
                }
            } else {
                ContentUnavailableView("Plugin not installed", systemImage: "puzzlepiece.extension")
            }
        }
        .navigationTitle(plugin?.name ?? "Plugin")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .confirmationDialog(
                "Remove this plugin?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await store.remove(pluginID)
                        dismiss()
                    }
                }
            } message: {
                Text("Songs that only play through this plugin will stop working until you reinstall it.")
            }
    }
}
