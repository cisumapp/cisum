//
//  ImportServiceSheet.swift
//  Library
//
//  Unified import entry: pick a service, multi-select playlists (or paste a link / pick files),
//  confirm → the Download Manager imports in the background and the sheet dismisses immediately.
//

import Aesthetics
import Kingfisher
import Models
import SwiftUI
import UniformTypeIdentifiers
import Utilities

public struct ImportServiceSheet: View {
    private enum Stage: Equatable { case pick, browse, link }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.importDownloadManager) private var manager

    @State private var stage: Stage = .pick
    @State private var provider: ImportProvider?
    @State private var refs: [ImportablePlaylistRef] = []
    @State private var selected: Set<String> = []
    @State private var linkText = ""
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var showFileImporter = false

    public init() {}

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if stage == .browse {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import \(selected.count)") { Task { await confirmSelected() } }
                                .disabled(selected.isEmpty || isSubmitting)
                        }
                        if provider == .youtube {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Link") { stage = .link }
                            }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.audio],
                    allowsMultipleSelection: true
                ) { result in
                    Task { await handleFiles(result) }
                }
                .alert("Import", isPresented: errorBinding) {
                    Button("OK", role: .cancel) { errorText = nil }
                } message: { Text(errorText ?? "") }
        }
    }

    private var navTitle: String {
        switch stage {
        case .pick: "Import"
        case .browse, .link: provider.map(Self.displayName) ?? "Import"
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .pick: servicePicker
        case .browse: playlistBrowser
        case .link: linkEntry
        }
    }

    // MARK: - Stage: pick service

    private var servicePicker: some View {
        List {
            Section("Choose a source") {
                serviceRow(.spotify, "Spotify", "music.note")
                serviceRow(.youtube, "YouTube", "play.rectangle")
                #if canImport(MusicKit)
                serviceRow(.appleMusic, "Apple Music", "applelogo")
                #endif
                serviceRow(.localFile, "Local Files", "folder")
            }
        }
    }

    private func serviceRow(_ p: ImportProvider, _ title: String, _ symbol: String) -> some View {
        Button { start(p) } label: {
            Label(title, systemImage: symbol)
        }
        .disabled(isLoading)
    }

    // MARK: - Stage: browse playlists (Spotify / Apple Music)

    @ViewBuilder private var playlistBrowser: some View {
        if isLoading {
            ProgressView("Loading playlists…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if refs.isEmpty {
            ContentUnavailableView("No playlists", systemImage: "music.note.list")
        } else {
            List(refs) { ref in
                Button { toggle(ref.id) } label: {
                    HStack {
                        rowThumbnail(ref)
                        VStack(alignment: .leading) {
                            Text(ref.title).foregroundStyle(.primary)
                            if let sub = ref.ownerName ?? ref.subtitle {
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let n = ref.trackCount { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
                        Image(systemName: selected.contains(ref.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(ref.id) ? Color.accentColor : Color.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func rowThumbnail(_ ref: ImportablePlaylistRef) -> some View {
        if let url = ref.artworkURL {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cisumChromeStrong)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: ref.id == "spotify:collection:tracks" ? "heart.fill" : "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Stage: link entry (YouTube)

    private var linkEntry: some View {
        Form {
            Section("Playlist link or ID") {
                TextField("https://… or playlist ID", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button {
                    Task { await importLink() }
                } label: {
                    HStack { Text("Import"); if isSubmitting { Spacer(); ProgressView() } }
                }
                .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
    }

    // MARK: - Actions

    private func start(_ p: ImportProvider) {
        provider = p
        selected.removeAll()
        refs = []
        PerfLog.info("ImportServiceSheet: picked \(p.rawValue)")
        Task {
            guard let manager, let svc = await manager.service(for: p) else {
                errorText = "That source isn't available."
                return
            }
            switch p {
            case .localFile:
                showFileImporter = true
            case .youtube:
                await loadPlaylists(svc)
                if refs.isEmpty {
                    errorText = nil // logged-out / empty library → paste-link is the intended path, not an error
                    stage = .link
                } else {
                    stage = .browse
                }
            case .spotify:
                if await svc.isAuthorized() {
                    await loadPlaylists(svc)
                    stage = .browse
                    await fillMissingCounts(svc) // libraryV3 can't return per-playlist counts; fetch lazily
                } else {
                    errorText = "Connect Spotify in Settings before importing."
                }
            case .appleMusic:
                var ok = await svc.isAuthorized()
                #if canImport(MusicKit)
                if !ok, let am = svc as? AppleMusicImportService { ok = await am.requestAuthorization() }
                #endif
                if ok {
                    await loadPlaylists(svc)
                    stage = .browse
                } else {
                    errorText = "Apple Music access was denied."
                }
            }
        }
    }

    private func loadPlaylists(_ svc: any ImportService) async {
        isLoading = true
        defer { isLoading = false }
        do {
            refs = try await svc.listImportablePlaylists(limit: 200)
            PerfLog.info("ImportServiceSheet: loaded \(refs.count) playlists")
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Spotify's library query doesn't return per-playlist track counts, so fetch them
    /// lazily via fetchMetadata and patch the rows in as they arrive (capped concurrency).
    private func fillMissingCounts(_ svc: any ImportService) async {
        let targets = refs.enumerated().filter { $0.element.trackCount == nil }
        await withTaskGroup(of: (Int, Int?).self) { group in
            var active = 0
            for (i, ref) in targets {
                if active >= 6 { _ = await group.next(); active -= 1 } // ponytail: 6-wide cap; raise if too slow
                active += 1
                group.addTask {
                    let count = try? await svc.fetchMetadata(playlistID: ref.id).totalTrackCount
                    return (i, count)
                }
            }
            for await (i, count) in group {
                guard let count, refs.indices.contains(i) else { continue }
                let r = refs[i]
                refs[i] = ImportablePlaylistRef(
                    id: r.id,
                    title: r.title,
                    subtitle: r.subtitle,
                    ownerName: r.ownerName,
                    artworkURL: r.artworkURL,
                    trackCount: count
                )
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func confirmSelected() async {
        guard let provider, let manager else { return }
        let chosen = refs.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isSubmitting = true
        PerfLog.info("ImportServiceSheet: enqueue \(chosen.count) playlist(s) from \(provider.rawValue)")
        await manager.enqueue(provider: provider, playlistRefs: chosen)
        dismiss()
    }

    private func importLink() async {
        guard let provider, let manager else { return }
        let link = linkText.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let svc = await manager.service(for: provider) else { throw ImportError.unsupported }
            let ref = try await svc.resolve(link: link)
            await manager.enqueue(provider: provider, playlistRef: ref)
            PerfLog.info("ImportServiceSheet: enqueued link import \(ref.title)")
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) async {
        guard let manager, let svc = await manager.service(for: .localFile) as? LocalFileImportService else { return }
        switch result {
        case let .success(urls) where !urls.isEmpty:
            isSubmitting = true
            do {
                let title = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Local Import (\(urls.count))"
                let ref = try svc.register(urls: urls, title: title)
                await manager.enqueue(provider: .localFile, playlistRef: ref)
                PerfLog.info("ImportServiceSheet: enqueued \(urls.count) local file(s)")
                dismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        case .success:
            break
        case let .failure(error):
            errorText = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    private static func displayName(_ p: ImportProvider) -> String {
        switch p {
        case .spotify: "Spotify"
        case .youtube: "YouTube"
        case .appleMusic: "Apple Music"
        case .localFile: "Local Files"
        }
    }
}
