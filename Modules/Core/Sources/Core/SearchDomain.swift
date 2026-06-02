import Caching
import Foundation
import Networking
import Player
import Search

public final class SearchDomain {
    let searchViewModel: SearchViewModel
    let historyStore: Search.SearchHistoryStore
    let searchCacheHintStore: SearchCacheHintStore
    let searchCache: any SearchResultsCaching
    let suggestionRanker: SuggestionRanker.Type

    public init(
        searchViewModel: SearchViewModel,
        historyStore: Search.SearchHistoryStore,
        searchCacheHintStore: SearchCacheHintStore,
        searchCache: any SearchResultsCaching,
        suggestionRanker: SuggestionRanker.Type
    ) {
        self.searchViewModel = searchViewModel
        self.historyStore = historyStore
        self.searchCacheHintStore = searchCacheHintStore
        self.searchCache = searchCache
        self.suggestionRanker = suggestionRanker
    }

    public func interface(networkMonitor: NetworkPathMonitor, prefetchSettings: PrefetchSettings) -> SearchInterface {
        SearchInterface(
            historyStore: historyStore,
            searchCacheHintStore: searchCacheHintStore,
            searchCache: searchCache,
            suggestionRanker: suggestionRanker,
            networkMonitor: networkMonitor,
            prefetchSettings: prefetchSettings,
            searchViewModel: searchViewModel
        )
    }
}
