//
//  LibraryUnavailableView.swift
//  Core
//
//  The failure state shown when the persistent library cannot be opened.
//
//  Before this existed, `AppBootstrap` caught the error and silently continued with an in-memory
//  container. From the user's point of view the library had simply vanished — the worst possible
//  presentation of a store problem, because there was no signal that anything was wrong and no
//  reason to believe the data still existed. This screen replaces that: it is explicit, it never
//  shows an empty library, and it never writes to the store.
//

import Aesthetics
import SwiftUI
import Utilities

#if os(macOS)
import AppKit
#endif

/// Why the persistent library could not be opened.
public struct LibraryOpenFailure: Sendable, Equatable {
    /// A short, user-facing headline.
    public let message: String

    /// Sanitised technical detail, shown behind a disclosure for diagnostics.
    public let technicalDescription: String

    public init(error: any Error) {
        self.message = "Cisum couldn't open your music library."
        self.technicalDescription = error.localizedDescription
    }
}

/// The recovery outcome of a retry attempt.
public enum LibraryRetryOutcome: Sendable, Equatable {
    /// The store opened. The app still needs to be relaunched to use it.
    case reopened
    /// The store still cannot be opened, with the (possibly unchanged) reason.
    case stillUnavailable(LibraryOpenFailure)
}

/// The full-screen failure state for an un-openable library.
///
/// Deliberately replaces the app shell rather than appearing over it: the alternative — the normal
/// UI backed by an empty store — is the exact outcome this exists to prevent.
public struct LibraryUnavailableView: View {
    private let failure: LibraryOpenFailure
    private let onRetry: @MainActor () async -> LibraryRetryOutcome

    @State private var outcome: LibraryRetryOutcome?
    @State private var isRetrying = false

    public init(
        failure: LibraryOpenFailure,
        onRetry: @escaping @MainActor () async -> LibraryRetryOutcome
    ) {
        self.failure = failure
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text(failure.message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(Self.reassurance(for: outcome))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task { await retry() }
                }
                .disabled(isRetrying)

                #if os(macOS)
                Button("Quit Cisum") {
                    NSApplication.shared.terminate(nil)
                }
                #endif
            }

            if case .reopened = outcome {
                Text("Reopen Cisum to continue.")
                    .font(.callout.weight(.medium))
            }

            DisclosureGroup("Technical details") {
                Text(failure.technicalDescription)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cisumBg.ignoresSafeArea())
    }

    private static func reassurance(for outcome: LibraryRetryOutcome?) -> String {
        switch outcome {
        case .none:
            // The single most important sentence on this screen: the user must know their data was
            // not deleted and that Cisum has not modified it.
            "Nothing on disk was changed. Your library is still there — Cisum just couldn't read it."
        case .reopened:
            "The library opened successfully."
        case let .stillUnavailable(failure):
            "It still couldn't be opened. \(failure.technicalDescription)"
        }
    }

    @MainActor
    private func retry() async {
        isRetrying = true
        outcome = await onRetry()
        isRetrying = false
    }
}
