#if os(iOS)
import Models
import SwiftUI

/// Picker for adding a track to one of the user's local playlists (or a brand-new one).
/// Driven entirely by the `\.savedLibrary` protocol so it can live in Player and be reused by
/// any module that imports Player (Playlists rows, search, etc.) without a Playlists dependency.
public struct AddToPlaylistSheet: View {
    let track: SavableTrack

    @Environment(\.savedLibrary) private var savedLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [LocalPlaylistRef] = []
    @State private var isCreating = false
    @State private var newName = ""

    public init(track: SavableTrack) {
        self.track = track
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle.fill")
                    }
                }

                if !playlists.isEmpty {
                    Section("Your Playlists") {
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist.id)
                            } label: {
                                Label(playlist.title, systemImage: "music.note.list")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { playlists = await savedLibrary?.localPlaylists() ?? [] }
            .alert("New Playlist", isPresented: $isCreating) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") { createAndAdd() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to playlistID: String) {
        Task {
            await savedLibrary?.addToPlaylist(track, playlistID: playlistID)
            dismiss()
        }
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty, let savedLibrary else { return }
        Task {
            let id = await savedLibrary.createLocalPlaylist(title: name)
            await savedLibrary.addToPlaylist(track, playlistID: id)
            dismiss()
        }
    }
}
#endif
