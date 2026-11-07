//
//  PlayerThemeSettings.swift
//  Player
//

#if os(iOS)
import Observation
import SwiftUI

/// Which player theme the user has chosen.
///
/// Persisted immediately rather than debounced: unlike a slider, this changes at most once per
/// user decision, and losing it because the app was suspended would be worse than the write.
@MainActor
@Observable
public final class PlayerThemeSettings {
    public static let shared = PlayerThemeSettings()

    public var selected: PlayerThemeID {
        didSet {
            guard selected != oldValue else { return }
            defaults.set(selected.rawValue, forKey: Key.selected)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // An unrecognised stored value means a theme was removed or renamed between builds.
        // Falling back is correct; the raw values are fixed precisely so this stays rare.
        self.selected = (defaults.string(forKey: Key.selected))
            .flatMap(PlayerThemeID.init(rawValue:)) ?? .default
    }

    private enum Key {
        static let selected = "player.theme.selected"
    }
}

/// Renders the selected theme.
///
/// A `PlayerTheme` has associated types, so it cannot be stored in a variable of protocol type.
/// This switches on the id instead — which also keeps the set of themes checked by the compiler,
/// so adding a case here without implementing it is a build error rather than a runtime surprise.
@MainActor
enum PlayerThemeRenderer {
    @ViewBuilder
    static func background(
        _ id: PlayerThemeID,
        expanded: Bool,
        fullyExpanded: Bool,
        collapsedHeight: CGFloat
    ) -> some View {
        switch id {
        case .default, .animatedArtwork:
            DefaultPlayerTheme(showsMotionArtwork: id == .animatedArtwork).background(
                expanded: expanded,
                fullyExpanded: fullyExpanded,
                collapsedHeight: collapsedHeight
            )
            .modifier(OnMediaAppearance(active: expanded))
        }
    }

    @ViewBuilder
    static func miniPlayer(
        _ id: PlayerThemeID,
        expanded: Binding<Bool>,
        namespace: Namespace.ID
    ) -> some View {
        switch id {
        case .default, .animatedArtwork:
            DefaultPlayerTheme().miniPlayer(expanded: expanded, namespace: namespace)
        }
    }

    @ViewBuilder
    static func expanded(
        _ id: PlayerThemeID,
        expanded: Bool,
        size: CGSize,
        namespace: Namespace.ID
    ) -> some View {
        switch id {
        case .default, .animatedArtwork:
            DefaultPlayerTheme().expanded(expanded: expanded, size: size, namespace: namespace)
                .modifier(OnMediaAppearance(active: true))
        }
    }
}

/// The open player always sits on artwork under a dark scrim, so it renders as dark mode in either
/// system appearance: its materials go dark and every token resolves to its light ink. In light mode
/// it was mixing near-black `.primary` lyrics with the controls' white. The collapsed pill keeps
/// following the app.
private struct OnMediaAppearance: ViewModifier {
    let active: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, active ? .dark : colorScheme)
    }
}
#endif
