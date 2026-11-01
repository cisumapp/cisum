//
//  SourceTrustPolicy.swift
//  PlaybackCore
//
//  Which provider cisum trusts, decided at runtime rather than by the provider itself.
//

import Foundation

/// cisum's runtime trust in a provider — the producer the ranking's trust tier was missing.
///
/// **Trust is not a provider's opinion of itself.** A JavaScript plugin cannot promote itself, a
/// declarative manifest cannot claim to be first-party, and a source that is not registered at all is
/// not "untrusted" — it is unknown, which is a different thing and the honest answer.
///
/// The tier is a tie-break *below* quality and delivery, so this only ever separates candidates that
/// are otherwise equal; it never lets cisum play a worse stream because it trusts the provider more.
public enum SourceTrustPolicy {
    /// The provider ids cisum compiles and ships itself.
    ///
    /// Native adapters are the ones with a maintained SDK behind them and a code path cisum can fix.
    /// **Adding a native adapter means adding its id here** — a provider that is not listed is treated
    /// as a user-installed plugin, which is the conservative direction.
    public static let nativeSourceIDs: Set<String> = [
        "youtube_music",
        "youtube",
    ]

    /// - Parameter isRegistered: Whether the source registry is currently serving this id. An id
    ///   nobody serves is `.unknown`, never `.thirdParty`.
    public static func trust(for sourceID: String, isRegistered: Bool) -> SourceTrust {
        if nativeSourceIDs.contains(sourceID) {
            return .firstParty
        }
        return isRegistered ? .thirdParty : .unknown
    }
}
