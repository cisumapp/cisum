//
//  HeadGestures.swift
//  Player
//
//  AirPods head gestures: a nod or a shake of the head controls playback.
//

import AudioToolbox
import CoreMotion
import PlaybackCore
import Utilities

/// What a head gesture does.
public enum HeadGestureAction: String, CaseIterable, Identifiable, Sendable {
    case nothing, playPause, next, previous, seekForward, seekBackward

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nothing: "Nothing"
        case .playPause: "Play/Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .seekForward: "Skip Forward 15 s"
        case .seekBackward: "Skip Back 15 s"
        }
    }
}

/// Listens to the head motion AirPods Pro, AirPods (3rd generation and later), AirPods Max and some
/// Beats report, and hands each detected gesture on.
///
/// The app's one `CMHeadphoneMotionManager`: iOS gives a manager's motion to one handler only.
@MainActor
final class HeadGestureController {
    private let manager = CMHeadphoneMotionManager()
    private var detector = HeadGestureDetector()
    private let onGesture: @MainActor (HeadGesture) -> Void
    private var isRunning = false

    init(onGesture: @escaping @MainActor (HeadGesture) -> Void) {
        self.onGesture = onGesture
    }

    /// Starts or stops listening. `sensitivity` is a percentage: 200 halves the movement needed.
    func setActive(_ active: Bool, sensitivity: Double) {
        detector.threshold = 1.6 * 100 / max(sensitivity, 1)
        guard active != isRunning else { return }
        isRunning = active
        guard active else {
            manager.stopDeviceMotionUpdates()
            return
        }
        // False without headphones that report motion. The first start asks for Motion permission.
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // ponytail: x is ear to ear (a nod), z is vertical (a shake), per CMHeadphoneMotionManager's
            // frame. Swap here if a device disagrees.
            let pitch = motion.rotationRate.x, yaw = motion.rotationRate.z, time = motion.timestamp
            MainActor.assumeIsolated {
                guard let self, let gesture = self.detector.feed(pitch: pitch, yaw: yaw, time: time) else { return }
                self.onGesture(gesture)
            }
        }
    }

    /// A short tick in the music, so a gesture is confirmed without looking at the phone.
    static func confirm() {
        AudioServicesPlaySystemSound(1104)
    }
}
