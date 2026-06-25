//
//  ImportProgressToastView.swift
//  Library
//
//  Top-anchored overlay: ONE aggregate "Importing N playlists — X/N" chip while a batch
//  runs, plus a single summary toast when the batch finishes. Mounted once near the app
//  root by the composition root.
//

import SwiftUI
import Models
import Utilities

public struct ImportProgressToastView: View {
    private let facade: ImportProgressFacade
    private let manager: ImportDownloadManager

    @State private var seenJobIDs: Set<String> = [] // every job observed in the current batch
    @State private var doneCount = 0
    @State private var failedCount = 0
    @State private var toast: String?
    @State private var clearTask: Task<Void, Never>?

    public init(facade: ImportProgressFacade, manager: ImportDownloadManager) {
        self.facade = facade
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 8) {
            if !facade.active.isEmpty {
                chip(text: aggregateText, systemImage: "arrow.down.circle")
            }
            if let toast {
                chip(text: toast, systemImage: "checkmark.circle.fill")
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.snappy, value: facade.active)
        .animation(.snappy, value: toast)
        .onChange(of: facade.active.map(\.id)) { _, ids in
            seenJobIDs.formUnion(ids) // batch grows as jobs enqueue
        }
        .task {
            for await event in manager.completions {
                doneCount += 1
                if event.state == .failed || event.state == .partialFailure { failedCount += 1 }
                if facade.active.isEmpty { showSummary() } // last job left the set
            }
        }
    }

    private var aggregateText: String {
        let total = max(seenJobIDs.count, facade.active.count + doneCount)
        return "Importing \(total) playlist\(total == 1 ? "" : "s") — \(doneCount)/\(total)"
    }

    private func showSummary() {
        let total = max(seenJobIDs.count, doneCount)
        let text = failedCount == 0
            ? "\(total) playlist\(total == 1 ? "" : "s") imported"
            : "\(total - failedCount)/\(total) imported — \(failedCount) failed"
        show(text)
        seenJobIDs.removeAll()
        doneCount = 0
        failedCount = 0
    }

    private func chip(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
    }

    private func show(_ text: String) {
        PerfLog.info("ImportProgressToastView: \(text)")
        toast = text
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }
}
