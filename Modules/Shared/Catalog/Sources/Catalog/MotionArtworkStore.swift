//
//  MotionArtworkStore.swift
//  Catalog
//
//  Animated artwork downloaded once and kept on the device: Spotify's Canvas when the user is
//  signed in to Spotify and the track has a Spotify ID, otherwise Apple Music's motion artwork.
//  One video per album, so every track on it shares the file.
//

import Foundation
import iTunesKit
import Models

public actor MotionArtworkStore {
    /// Fetches a Spotify track's Canvas URL; `nil` when signed out or the track has none.
    public typealias CanvasLookup = @Sendable (_ spotifyTrackID: String) async -> URL?

    /// Kept under this; the least recently played videos go first.
    static let budget: Int64 = 300 * 1024 * 1024
    /// An album with no animated artwork is not asked about again for a week.
    static let missRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    nonisolated let directory: URL
    private let canvasLookup: CanvasLookup?
    private let itunes = iTunesKit()
    private var inFlight: [String: Task<URL?, Never>] = [:]

    public init(canvasLookup: CanvasLookup?) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("MotionArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.canvasLookup = canvasLookup
    }

    /// What the views use.
    public nonisolated var source: MotionArtworkSource {
        MotionArtworkSource(
            cachedVideo: { [self] in cachedVideo(for: $0) },
            fetch: { [self] in await fetch($0) }
        )
    }

    // MARK: Cache

    nonisolated func cachedVideo(for request: MotionArtworkRequest) -> URL? {
        let file = videoURL(Self.key(request))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        // Marks it recently used, for the eviction below.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    /// One video per album: the album when it is known, the track otherwise.
    nonisolated static func key(_ request: MotionArtworkRequest) -> String {
        let name = "\(request.artist)|\(request.album ?? request.title)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // FNV-1a: stable across launches, unlike `hashValue`.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    private nonisolated func videoURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).mp4")
    }

    private nonisolated func missURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).miss")
    }

    // MARK: Fetch

    func fetch(_ request: MotionArtworkRequest) async -> URL? {
        if let cached = cachedVideo(for: request) { return cached }
        let key = Self.key(request)
        if let task = inFlight[key] { return await task.value }
        if let missed = try? FileManager.default.attributesOfItem(atPath: missURL(key).path)[.modificationDate] as? Date,
           Date().timeIntervalSince(missed) < Self.missRetryInterval
        {
            return nil
        }

        let task = Task { await download(request, key: key) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func download(_ request: MotionArtworkRequest, key: String) async -> URL? {
        var data: Data?
        if let trackID = request.spotifyTrackID, let canvas = await canvasLookup?(trackID) {
            data = try? await URLSession.shared.data(from: canvas).0
        }
        if data == nil,
           let resolution = try? await itunes.resolveMotionArtwork(term: "\(request.album ?? request.title) \(request.artist)")
        {
            data = try? await Self.downloadHLS(resolution.sourceURL)
        }

        guard let data, !data.isEmpty else {
            FileManager.default.createFile(atPath: missURL(key).path, contents: nil)
            return nil
        }
        let file = videoURL(key)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            return nil
        }
        evictIfNeeded()
        return file
    }

    /// Apple's motion artwork is HLS with fragmented MP4 segments. The initialisation segment
    /// followed by the media segments is itself a playable fragmented MP4, so one variant is
    /// fetched and joined into a single file — simpler than an offline asset download, and one
    /// file per album to keep and evict.
    ///
    /// Some of these videos run minutes long; the first `maxDuration` seconds loop well enough as
    /// a background and keep a file near 15 MB instead of 50.
    static func downloadHLS(_ playlist: URL, maxDuration: Double = 60) async throws -> Data? {
        let text = try await String(decoding: URLSession.shared.data(from: playlist).0, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        // A multivariant playlist: HEVC near 2 Mbit/s (664×886, as sharp for less), else H.264
        // near 1.5 Mbit/s.
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            var variants: [(bandwidth: Int, isHEVC: Bool, url: URL)] = []
            for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
                guard index + 1 < lines.count, let url = URL(string: lines[index + 1], relativeTo: playlist) else { continue }
                let bandwidth = line.range(of: #"(?<![A-Z-])BANDWIDTH=(\d+)"#, options: .regularExpression)
                    .flatMap { Int(line[$0].split(separator: "=").last ?? "") } ?? 0
                variants.append((bandwidth, line.contains("hvc1"), url))
            }
            let hevc = variants.filter(\.isHEVC)
            let pool = hevc.isEmpty ? variants : hevc
            let target = hevc.isEmpty ? 1_500_000 : 2_000_000
            guard let best = pool.min(by: { abs($0.bandwidth - target) < abs($1.bandwidth - target) }) else { return nil }
            return try await downloadHLS(best.url.absoluteURL, maxDuration: maxDuration)
        }

        guard let mapLine = lines.first(where: { $0.hasPrefix("#EXT-X-MAP") }),
              let range = mapLine.range(of: #"URI="([^"]+)""#, options: .regularExpression),
              let initURL = URL(string: String(mapLine[range].dropFirst(5).dropLast()), relativeTo: playlist)
        else { return nil }

        // Segments up to the duration cap, in order.
        var segments: [URL] = []
        var duration = 0.0
        var nextDuration = 0.0
        for line in lines {
            if line.hasPrefix("#EXTINF:") {
                nextDuration = Double(line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? "") ?? 0
            } else if !line.isEmpty, !line.hasPrefix("#"), let url = URL(string: line, relativeTo: playlist) {
                guard duration < maxDuration else { break }
                segments.append(url.absoluteURL)
                duration += nextDuration
            }
        }

        // Byte-range playlists (`#EXT-X-BYTERANGE`) name one file for the init segment and every
        // media segment: that file is already the whole video, so it is fetched once.
        if Set(segments) == [initURL.absoluteURL] {
            return try await URLSession.shared.data(from: initURL.absoluteURL).0
        }

        // Fetched a few at a time, then joined in playlist order.
        var parts = [Data?](repeating: nil, count: segments.count)
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var next = 0
            func enqueue() {
                guard next < segments.count else { return }
                let index = next, url = segments[index]
                next += 1
                group.addTask { (index, try await URLSession.shared.data(from: url).0) }
            }
            for _ in 0 ..< 6 { enqueue() }
            while let (index, data) = try await group.next() {
                parts[index] = data
                enqueue()
            }
        }

        var file = try await URLSession.shared.data(from: initURL.absoluteURL).0
        for part in parts {
            guard let part else { return nil }
            file.append(part)
        }
        return file
    }

    private func evictIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            .filter({ $0.pathExtension == "mp4" })
        else { return }
        let entries = files.compactMap { url -> (url: URL, size: Int64, used: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.used < $1.used }) where total > Self.budget {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
