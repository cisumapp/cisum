import Observation
import SwiftUI

enum OverlaySearchScope: Hashable, Identifiable {
    case global
    case playlist(id: String, title: String)

    var id: String {
        switch self {
        case .global:
            return "global"
        case .playlist(let id, _):
            return "playlist-\(id)"
        }
    }

    var title: String {
        switch self {
        case .global:
            return "Global"
        case .playlist(_, let title):
            return title
        }
    }

    var symbolName: String {
        switch self {
        case .global:
            return "globe"
        case .playlist:
            return "music.note.list"
        }
    }

    var prompt: String {
        switch self {
        case .global:
            return "Search songs, artists, and videos"
        case .playlist(_, let title):
            return "Search in \(title)"
        }
    }

    var isGlobal: Bool {
        if case .global = self {
            return true
        }
        return false
    }
}

struct SearchOverlayContext: Equatable {
    var availableScopes: [OverlaySearchScope]
    var preferredScope: OverlaySearchScope

    static let global = SearchOverlayContext(
        availableScopes: [.global],
        preferredScope: .global
    )

    static func playlist(playlistID: String, playlistTitle: String) -> SearchOverlayContext {
        let playlistScope = OverlaySearchScope.playlist(id: playlistID, title: playlistTitle)
        return SearchOverlayContext(
            availableScopes: [playlistScope, .global],
            preferredScope: playlistScope
        )
    }
}

struct SearchOverlayContextPreferenceKey: PreferenceKey {
    static let defaultValue: SearchOverlayContext = .global

    static func reduce(value: inout SearchOverlayContext, nextValue: () -> SearchOverlayContext) {
        value = nextValue()
    }
}

extension View {
    func searchOverlayContext(_ context: SearchOverlayContext) -> some View {
        preference(key: SearchOverlayContextPreferenceKey.self, value: context)
    }
}

@Observable
@MainActor
final class SearchOverlayController {
    var query: String = ""
    var context: SearchOverlayContext = .global
    var selectedScope: OverlaySearchScope = .global
    var focusRequestID: Int = 0

    private var globalQuery: String = ""
    private var playlistQueries: [String: String] = [:]

    var canSwitchToGlobalFromShortcut: Bool {
        !selectedScope.isGlobal && context.availableScopes.contains(.global)
    }

    func present() {
        focusRequestID += 1
    }

    func updateContext(_ newContext: SearchOverlayContext) {
        guard context != newContext else { return }
        persistCurrentQuery()

        context = newContext
        selectedScope = newContext.preferredScope
        query = storedQuery(for: selectedScope)
    }

    func selectScope(_ scope: OverlaySearchScope) {
        guard selectedScope != scope else { return }
        persistCurrentQuery()

        selectedScope = scope
        query = storedQuery(for: scope)
        focusRequestID += 1
    }

    func switchToGlobalScope(carryCurrentQuery: Bool) {
        guard context.availableScopes.contains(.global) else { return }
        let currentQuery = query

        selectScope(.global)
        if carryCurrentQuery {
            updateActiveQuery(currentQuery)
        }
    }

    func updateActiveQuery(_ newValue: String) {
        query = newValue
        persistCurrentQuery()
    }

    func playlistQuery(for playlistID: String) -> String {
        playlistQueries[playlistID] ?? ""
    }

    private func persistCurrentQuery() {
        switch selectedScope {
        case .global:
            globalQuery = query
        case .playlist(let id, _):
            playlistQueries[id] = query
        }
    }

    private func storedQuery(for scope: OverlaySearchScope) -> String {
        switch scope {
        case .global:
            return globalQuery
        case .playlist(let id, _):
            return playlistQueries[id] ?? ""
        }
    }
}

struct SearchOverlayBar: View {
    @Environment(SearchOverlayController.self) private var searchOverlay
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(\.router) private var router

    @FocusState private var isSearchFieldFocused: Bool

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if searchOverlay.context.availableScopes.count > 1 {
                scopeSelector
            }

            if shouldShowSuggestions {
                suggestionsPanel
            }
        }
        .onChange(of: searchOverlay.focusRequestID) { _, _ in
            isSearchFieldFocused = true
        }
        .enableInjection()
    }

    private var shouldShowSuggestions: Bool {
        searchOverlay.selectedScope.isGlobal
        && isSearchFieldFocused
        && !searchOverlay.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !searchViewModel.suggestions.isEmpty
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(searchOverlay.selectedScope.prompt, text: queryBinding)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    submitSearch()
                }

            if !searchOverlay.query.isEmpty {
                Button {
                    queryBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 260)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 50, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 50))
            } else {
                RoundedRectangle(cornerRadius: 50, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 50, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
    }

    private var scopeSelector: some View {
        HStack(spacing: 8) {
            ForEach(searchOverlay.context.availableScopes) { scope in
                let isSelected = searchOverlay.selectedScope == scope

                Button {
                    searchOverlay.selectScope(scope)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scope.symbolName)
                        Text(scope.title)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(isSelected ? .white.opacity(0.22) : .white.opacity(0.08))
                    }
                }
                .buttonStyle(.plain)
            }

            if searchOverlay.canSwitchToGlobalFromShortcut {
                Button {
                    switchToGlobalAndSearch()
                } label: {
                    Text("Global (Cmd+Enter)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(8)
        .frame(width: 560, alignment: .leading)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(searchViewModel.suggestions.prefix(6)), id: \.self) { suggestion in
                Button {
                    searchOverlay.updateActiveQuery(suggestion)
                    if searchViewModel.searchText != suggestion {
                        searchViewModel.searchText = suggestion
                    }
                    submitSearch()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(suggestion)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 560)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { searchOverlay.query },
            set: { newValue in
                searchOverlay.updateActiveQuery(newValue)
                guard searchOverlay.selectedScope.isGlobal else { return }
                if searchViewModel.searchText != newValue {
                    searchViewModel.searchText = newValue
                }
            }
        )
    }

    private func switchToGlobalAndSearch() {
        searchOverlay.switchToGlobalScope(carryCurrentQuery: true)
        submitSearch()
    }

    private func submitSearch() {
        let trimmedQuery = searchOverlay.query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchOverlay.updateActiveQuery(trimmedQuery)

        switch searchOverlay.selectedScope {
        case .global:
            if router.selectedTab != .search {
                router.selectedTab = .search
            }

            if searchViewModel.searchText != trimmedQuery {
                searchViewModel.searchText = trimmedQuery
            } else {
                searchViewModel.performDebouncedSearch()
            }

        case .playlist:
            break
        }
    }
}
