//
//  AudioSession.swift
//  Player
//
//  The single place the audio session is configured.
//

import Foundation
import Utilities

#if canImport(AVFAudio) && !os(macOS)
import AVFAudio

/// Configures and observes the shared audio session.
///
/// **One configuration point, deliberately.** The previous implementation set the category in two
/// separate files (`PlaybackEngine` and a `PlayerViewModel` extension), which meant whichever ran
/// last won and interruption handling was split across both.
@MainActor
public enum AudioSession {
    /// Configures for long-form music playback. Idempotent; safe to call more than once.
    public static func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio
            )
        } catch {
            PerfLog.error("Could not configure the audio session: \(error.localizedDescription)")
        }
    }

    /// Activates the session.
    ///
    /// Called at the moment playback actually starts rather than at launch, so cisum does not
    /// interrupt whatever else the user is listening to just by being opened.
    public static func activate() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            PerfLog.error("Could not activate the audio session: \(error.localizedDescription)")
        }
    }

    public static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Observes interruptions (a phone call) and route changes (headphones unplugged).
    ///
    /// - Parameter onInterruption: `true` when playback should stop, `false` when it may resume.
    ///   Resumption is only suggested when the system sets `.shouldResume`; honouring that rather
    ///   than always resuming is what stops music restarting after the user deliberately paused it
    ///   via another app.
    public static func observe(onInterruption: @escaping @MainActor (Bool) -> Void) -> [NSObjectProtocol] {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            // Read everything out of the notification here, in the nonisolated callback.
            // `Notification` is not Sendable, so carrying it into the isolated closure below is a
            // data-race diagnostic under Swift 6; these two scalars are fine to hand over.
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            let shouldResume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) }
                ?? false

            MainActor.assumeIsolated {
                switch type {
                case .began:
                    onInterruption(true)
                case .ended:
                    onInterruption(!shouldResume)
                @unknown default:
                    break
                }
            }
        }

        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable
            else { return }

            // Headphones pulled out. Pausing is the expected behaviour; continuing on the speaker
            // is the thing users complain about.
            MainActor.assumeIsolated { onInterruption(true) }
        }

        return [interruption, route]
    }
}

#else

/// macOS has no `AVAudioSession`; the system manages routing itself.
@MainActor
public enum AudioSession {
    public static func configure() {}
    public static func activate() {}
    public static func deactivate() {}

    public static func observe(onInterruption _: @escaping @MainActor (Bool) -> Void) -> [NSObjectProtocol] {
        []
    }
}

#endif
