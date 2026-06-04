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
        searchable(text: text, placement: .toolbar) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSuggestionTap?(suggestion)
                } label: {
                    Text(suggestion)
                }
            }
        }
        #else
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
        #endif
    }
}
