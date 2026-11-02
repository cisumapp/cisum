//
//  HeadGestureDetector.swift
//  PlaybackCore
//
//  Nods and head shakes, out of headphone motion.
//

import Foundation

/// A deliberate head gesture.
public enum HeadGesture: String, Sendable {
    /// Two nods: down, up, down, up.
    case nod
    /// Left, right, left (or the mirror).
    case shake
}

/// Turns a stream of head rotation rates into gestures.
///
/// A gesture is a run of swings on one axis, each swing being the rate passing the threshold in the
/// direction opposite to the last one. Requiring alternation is what keeps a single turn of the
/// head (to look at something) or walking's steady bob from counting; requiring the axis to
/// dominate the other keeps a nod from also reading as a shake.
///
/// Pure value type, fed one sample at a time, so it is testable with synthetic motion.
public struct HeadGestureDetector: Sendable {
    /// Rad/s a swing must pass. Lower is more sensitive.
    public var threshold: Double

    /// Swings of a gesture must all fall within this many seconds.
    static let window = 1.2
    static let nodSwings = 4
    static let shakeSwings = 3
    /// Quiet time after a gesture, so its own tail does not start the next.
    static let cooldown = 1.0

    private var pitch = Axis()
    private var yaw = Axis()
    private var quietUntil = -Double.infinity

    public init(threshold: Double = 1.6) {
        self.threshold = threshold
    }

    /// Feeds one sample: rotation rate about the ear-to-ear axis (`pitch`, a nod) and the vertical
    /// axis (`yaw`, a shake), in rad/s, at `time` seconds. Returns a gesture when one completes.
    public mutating func feed(pitch pitchRate: Double, yaw yawRate: Double, time: Double) -> HeadGesture? {
        guard time >= quietUntil else { return nil }

        // Only the dominant axis may swing on a sample.
        let pitchLeads = abs(pitchRate) >= abs(yawRate)
        let gesture: HeadGesture?
        if pitchLeads {
            gesture = pitch.feed(pitchRate, threshold: threshold, time: time) >= Self.nodSwings ? .nod : nil
        } else {
            gesture = yaw.feed(yawRate, threshold: threshold, time: time) >= Self.shakeSwings ? .shake : nil
        }

        if gesture != nil {
            pitch = Axis()
            yaw = Axis()
            quietUntil = time + Self.cooldown
        }
        return gesture
    }

    private struct Axis: Sendable {
        var swings: [(sign: Double, time: Double)] = []

        /// Records a swing if this sample is one; returns the swings inside the window.
        mutating func feed(_ rate: Double, threshold: Double, time: Double) -> Int {
            swings.removeAll { time - $0.time > HeadGestureDetector.window }
            guard abs(rate) >= threshold else { return swings.count }
            let sign: Double = rate > 0 ? 1 : -1
            if swings.last?.sign != sign {
                swings.append((sign, time))
            }
            return swings.count
        }
    }
}
