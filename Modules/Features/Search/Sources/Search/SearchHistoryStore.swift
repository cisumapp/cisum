import Foundation
import Models
import Observation
import Search
import SwiftData

public struct SearchHistoryEntrySnapshot: Sendable {
    public let query: String
    public let searchCount: Int
    public let successfulPlayCount: Int
    public let lastSearchedAt: Date

    public init(query: String, searchCount: Int, successfulPlayCount: Int, lastSearchedAt: Date) {
        self.query = query
        self.searchCount = searchCount
        self.successfulPlayCount = successfulPlayCount
        self.lastSearchedAt = lastSearchedAt
    }
}

@ModelActor
public actor SearchHistoryStore {
    public func recordSearch(query: String) {
        let normalized = normalizedQuery(query)
        guard !normalized.isEmpty else { return }

        if let existing = fetchEntry(for: normalized) {
            existing.searchCount += 1
            existing.lastSearchedAt = .now
            existing.query = query
        } else {
            let entry = SearchHistoryEntry(
                query: query,
                normalizedQuery: normalized,
                searchCount: 1,
                successfulPlayCount: 0,
                lastSearchedAt: .now
            )
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    public func recordSuccessfulPlay(query: String) {
        let normalized = normalizedQuery(query)
        guard !normalized.isEmpty else { return }

        if let existing = fetchEntry(for: normalized) {
            existing.successfulPlayCount += 1
            existing.lastSearchedAt = .now
            try? modelContext.save()
        }
    }

    public func removeSearch(query: String) {
        let normalized = normalizedQuery(query)
        if let existing = fetchEntry(for: normalized) {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    public func topCandidates(prefix: String, limit: Int = 20) -> [SearchHistoryEntrySnapshot] {
        guard limit > 0 else { return [] }

        let normalizedPrefix = normalizedQuery(prefix)
        let descriptor = if normalizedPrefix.isEmpty {
            FetchDescriptor<SearchHistoryEntry>(sortBy: rankingSortDescriptors)
        } else {
            FetchDescriptor<SearchHistoryEntry>(
                predicate: #Predicate<SearchHistoryEntry> { entry in
                    entry.normalizedQuery.contains(normalizedPrefix)
                },
                sortBy: rankingSortDescriptors
            )
        }

        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = limit
        let entries = (try? modelContext.fetch(limitedDescriptor)) ?? []
        return entries.map {
            SearchHistoryEntrySnapshot(
                query: $0.query,
                searchCount: $0.searchCount,
                successfulPlayCount: $0.successfulPlayCount,
                lastSearchedAt: $0.lastSearchedAt
            )
        }
    }

    private func fetchEntry(for normalized: String) -> SearchHistoryEntry? {
        var descriptor = FetchDescriptor<SearchHistoryEntry>(
            predicate: #Predicate { $0.normalizedQuery == normalized }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var rankingSortDescriptors: [SortDescriptor<SearchHistoryEntry>] {
        [
            SortDescriptor(\SearchHistoryEntry.successfulPlayCount, order: .reverse),
            SortDescriptor(\SearchHistoryEntry.searchCount, order: .reverse),
            SortDescriptor(\SearchHistoryEntry.lastSearchedAt, order: .reverse),
        ]
    }
}
