import YouTubeSDK
import SwiftUI
import Kingfisher

struct SearchView: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.playerPresentationActions) private var playerPresentationActions

    @State private var showNonPlayableAlert: Bool = false
    @State private var nonPlayableMessage: String = ""

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        searchContent
            .safeAreaPadding(.top, 8)
            .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
                Button("OK", role: .cancel) { }
            }
            .enableInjection()
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            ZStack {
                switch searchViewModel.state {
                case .idle:
                    ContentUnavailableView("Search for something", systemImage: "magnifyingglass")

                case .loading:
                    ProgressView("Searching across services...")
                        .controlSize(.large)

                case .error(let message):
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))

                case .success:
                    ResultsList()
                }
            }
        }
        .enableInjection()
    }

    @ViewBuilder
    private func ResultsList() -> some View {
        List {
            Section {
                if searchViewModel.unifiedTopResults.isEmpty {
                    Text("No results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(searchViewModel.unifiedTopResults) { item in
                        Button {
                            handleRowSelection(item)
                        } label: {
                            federatedRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Results")
                    Text("Unified across Tidal, YouTube Music, and YouTube")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !searchViewModel.youMightLikeResults.isEmpty {
                Section {
                    ForEach(searchViewModel.youMightLikeResults) { item in
                        Button {
                            handleRowSelection(item)
                        } label: {
                            federatedRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You Might Like This")
                        if let anchorTitle = searchViewModel.unifiedTopResults.first?.title {
                            Text("Similar to \"\(anchorTitle)\"")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .enableInjection()
    }

    private func handleRowSelection(_ item: FederatedSearchItem) {
        switch item.payload {
        case .youtubeMusic(let song):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            let queue = searchViewModel.items(for: .youtubeMusic).compactMap { entry -> YouTubeMusicSong? in
                guard case .youtubeMusic(let queueSong) = entry.payload else { return nil }
                return queueSong
            }
            playerViewModel.load(song: song, in: queue, source: .searchMusic)
            playerPresentationActions.expand()

        case .youtubeVideo(let video):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            let queue = searchViewModel.items(for: .youtube).compactMap { entry -> YouTubeVideo? in
                guard case .youtubeVideo(let queueVideo) = entry.payload else { return nil }
                return queueVideo
            }
            playerViewModel.load(video: video, in: queue, source: .searchVideo)
            playerPresentationActions.expand()

        case .tidal, .spotify:
            Task {
                await playExternalStream(from: item)
            }
        }
    }

    @MainActor
    private func playExternalStream(from item: FederatedSearchItem) async {
        do {
            guard let selectedPayload = try await searchViewModel.resolveExternalStream(for: item) else {
                return
            }

            let serviceQueueItems = searchViewModel
                .items(for: item.service)
                .filter { $0.service == item.service }
            let queueTracks = makeExternalQueueTracks(
                from: serviceQueueItems,
                selectedItemID: item.id,
                selectedPayload: selectedPayload
            )

            guard let selectedTrack = queueTracks.first(where: { $0.mediaID == selectedPayload.mediaID })
                    ?? queueTracks.first(where: { $0.mediaID == item.id }) else {
                throw FederatedSearchError.noPlayableStream("Unable to build an external playback queue for this track.")
            }

            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(
                external: selectedTrack,
                in: queueTracks,
                source: .searchExternal
            )
            playerPresentationActions.expand()
        } catch {
            nonPlayableMessage = error.localizedDescription
            showNonPlayableAlert = true
        }
    }

    private func makeExternalQueueTracks(
        from items: [FederatedSearchItem],
        selectedItemID: String,
        selectedPayload: ExternalStreamPayload
    ) -> [PlayerViewModel.ExternalQueueTrack] {
        let tracks = items.compactMap { entry in
            makeExternalQueueTrack(
                for: entry,
                preResolvedPayload: entry.id == selectedItemID ? selectedPayload : nil
            )
        }

        if tracks.isEmpty {
            let fallbackTrack = PlayerViewModel.ExternalQueueTrack(
                mediaID: selectedPayload.mediaID,
                title: selectedPayload.title,
                artist: selectedPayload.artist,
                artworkURL: selectedPayload.artworkURL,
                service: selectedPayload.service,
                isExplicit: false,
                qualityLabelHint: selectedPayload.qualityLabel,
                codecLabelHint: selectedPayload.codecLabel,
                resolvePayload: {
                    selectedPayload
                }
            )
            return [fallbackTrack]
        }

        return tracks
    }

    private func makeExternalQueueTrack(
        for item: FederatedSearchItem,
        preResolvedPayload: ExternalStreamPayload? = nil
    ) -> PlayerViewModel.ExternalQueueTrack? {
        switch item.payload {
        case .tidal, .spotify:
            break
        case .youtubeMusic, .youtubeVideo:
            return nil
        }

        let artist = primaryArtistName(from: item.subtitle)
        let mediaID = preResolvedPayload?.mediaID ?? item.id

        return PlayerViewModel.ExternalQueueTrack(
            mediaID: mediaID,
            title: preResolvedPayload?.title ?? item.title,
            artist: preResolvedPayload?.artist ?? artist,
            artworkURL: preResolvedPayload?.artworkURL ?? item.artworkURL,
            service: preResolvedPayload?.service ?? item.service,
            isExplicit: item.isExplicit,
            qualityLabelHint: preResolvedPayload?.qualityLabel ?? item.audioQualityLabel,
            codecLabelHint: preResolvedPayload?.codecLabel ?? item.audioCodecLabel,
            resolvePayload: { [searchViewModel] in
                if let preResolvedPayload {
                    return preResolvedPayload
                }

                guard let payload = try await searchViewModel.resolveExternalStream(for: item) else {
                    throw FederatedSearchError.noPlayableStream("Unable to resolve a playable stream for this track.")
                }
                return payload
            }
        )
    }

    private func primaryArtistName(from subtitle: String) -> String {
        if let first = subtitle.split(separator: "•").first {
            let artist = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty {
                return artist
            }
        }

        return subtitle
    }

    @ViewBuilder
    private func federatedRow(_ item: FederatedSearchItem) -> some View {
        HStack(spacing: 12) {
            KFImage(item.artworkURL)
                .downsampling(size: CGSize(width: 100, height: 100))
                .placeholder {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.gray.opacity(0.2))
                }
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.isExplicit || item.audioQualityLabel != nil || item.audioCodecLabel != nil {
                    searchMetadataBadges(for: item)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let duration = item.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if !item.isPlayable {
                    Text("Metadata")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .contentShape(.rect)
        .cisumGlassCard(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }

    @ViewBuilder
    private func searchMetadataBadges(for item: FederatedSearchItem) -> some View {
        HStack(spacing: 6) {
            searchBadge(title: item.service.rawValue, tint: .secondary.opacity(0.12), textColor: .secondary)

            if item.isExplicit {
                searchBadge(title: "Explicit", tint: .red.opacity(0.16), textColor: .red)
            }

            if let quality = item.audioQualityLabel {
                searchBadge(title: quality, tint: .blue.opacity(0.14), textColor: .blue)
            }

            if let codec = item.audioCodecLabel {
                searchBadge(title: codec, tint: .secondary.opacity(0.16), textColor: .secondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func searchBadge(title: String, tint: Color, textColor: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(textColor)
            .accessibilityLabel(title)
    }
}

#Preview {
    SearchView()
        .injectPreviewDependencies()
}
