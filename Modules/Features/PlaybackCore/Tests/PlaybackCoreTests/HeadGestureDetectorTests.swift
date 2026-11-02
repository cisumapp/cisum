//
//  HeadGestureDetectorTests.swift
//  PlaybackCoreTests
//

import Foundation
@testable import PlaybackCore
import Testing

@Suite("Head gestures")
struct HeadGestureDetectorTests {
    /// Feeds `seconds` of motion at 50 Hz and returns every gesture detected.
    private func run(
        _ detector: inout HeadGestureDetector,
        seconds: Double,
        from start: Double = 0,
        motion: (Double) -> (pitch: Double, yaw: Double)
    ) -> [HeadGesture] {
        stride(from: start, to: start + seconds, by: 0.02).compactMap { t in
            let m = motion(t - start)
            return detector.feed(pitch: m.pitch, yaw: m.yaw, time: t)
        }
    }

    /// A head swinging back and forth at `hz`, peaking at `peak` rad/s.
    private func swing(_ t: Double, hz: Double, peak: Double = 3) -> Double {
        peak * sin(2 * .pi * hz * t)
    }

    @Test("a double nod is a nod, once")
    func doubleNod() {
        var detector = HeadGestureDetector()
        let gestures = run(&detector, seconds: 1.2) { (swing($0, hz: 2), 0.3) }
        #expect(gestures == [.nod])
    }

    @Test("left-right-left is a shake")
    func shake() {
        var detector = HeadGestureDetector()
        let gestures = run(&detector, seconds: 1.0) { (0.2, swing($0, hz: 1.6)) }
        #expect(gestures == [.shake])
    }

    @Test("a single nod, one turn of the head, or slow movement is nothing")
    func nonGestures() {
        var detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 0.5) { (swing($0, hz: 2), 0) }.isEmpty)
        detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 1) { (0, $0 < 0.3 ? 3 : 0) }.isEmpty)
        detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 3) { (swing($0, hz: 2, peak: 1), swing($0, hz: 1, peak: 1)) }.isEmpty)
    }

    @Test("swings spread too far apart do not add up")
    func window() {
        var detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 4) { (swing($0, hz: 0.4), 0) }.isEmpty)
    }

    @Test("a nod does not also read as a shake, and a lower threshold catches a gentler nod")
    func dominanceAndSensitivity() {
        var detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 1.2) { (swing($0, hz: 2), swing($0, hz: 2, peak: 2)) } == [.nod])
        detector = HeadGestureDetector()
        #expect(run(&detector, seconds: 1.2) { (swing($0, hz: 2, peak: 1.3), 0) }.isEmpty)
        detector = HeadGestureDetector(threshold: 1.0)
        #expect(run(&detector, seconds: 1.2) { (swing($0, hz: 2, peak: 1.3), 0) } == [.nod])
    }
}
