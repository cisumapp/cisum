import SwiftUI

public extension View {
    @ViewBuilder
    func optionalSearchable(
        text: Binding<String>,
        isFocused _: FocusState<Bool>.Binding? = nil,
        isPresented _: Binding<Bool>? = nil,
        suggestions: [String] = [],
        onSuggestionTap: ((String) -> Void)? = nil
    ) -> some View {
        #if os(macOS)
        // No-op on macOS. `searchable(placement: .toolbar)` asks AppKit for a toolbar item,
        // which materialises as a bar across the top of the window — exactly the chrome the
        // macOS shell is trying not to have, and it only ever appeared on the Search tab.
        //
        // macOS gets its search field from `SearchOverlayBar`, which the shell floats over
        // the content and binds to the same `searchViewModel.searchText`.
        self
        #else
        if #available(iOS 26.0, *) {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search music"
            ) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestionTap?(suggestion)
                    } label: {
                        Label(suggestion, systemImage: "magnifyingglass")
                    }
                }
            }
        } else {
            self
        }
        #endif
    }
}
