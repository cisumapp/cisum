//
//  EqualizerTests.swift
//  PlaybackCoreTests
//

import Accelerate
import Foundation
@testable import PlaybackCore
import Testing

@Suite("Equalizer")
struct EqualizerTests {
    /// |H(e^jw)| in dB for vDSP-ordered coefficients.
    private func responseDB(_ c: [Double], at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        func poly(_ k0: Double, _ k1: Double, _ k2: Double) -> (Double, Double) {
            (k0 + k1 * cos(w) + k2 * cos(2 * w), -(k1 * sin(w) + k2 * sin(2 * w)))
        }
        let num = poly(c[0], c[1], c[2]), den = poly(1, c[3], c[4])
        let magnitude = sqrt(num.0 * num.0 + num.1 * num.1) / sqrt(den.0 * den.0 + den.1 * den.1)
        return 20 * log10(magnitude)
    }

    @Test("each band's filter reaches its gain at its centre and leaves far frequencies alone")
    func peakingResponse() {
        for gain: Float in [-12, -3, 6, 12] {
            for frequency in Equalizer.frequencies {
                let c = Equalizer.peaking(gain: gain, frequency: frequency, sampleRate: 48000)
                #expect(abs(responseDB(c, at: frequency, sampleRate: 48000) - Double(gain)) < 0.01)
            }
        }
        let bass = Equalizer.peaking(gain: 12, frequency: 64, sampleRate: 44100)
        #expect(abs(responseDB(bass, at: 8000, sampleRate: 44100)) < 0.1)
    }

    @Test("a flat setting is a no-op and a boost is offset by the preamp")
    func filterOnSamples() {
        var samples = [Float](repeating: 0.5, count: 64)
        var delay = [Float](repeating: 0, count: 22)
        let flat = Equalizer.Filter(gains: Array(repeating: 0, count: 10), sampleRate: 48000)
        #expect(flat.setup == nil && flat.preamp == 1)
        flat.apply(&samples, count: 64, delay: &delay)
        #expect(samples.allSatisfy { $0 == 0.5 })

        let boosted = Equalizer.Filter(gains: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], sampleRate: 48000)
        #expect(abs(boosted.preamp - pow(10, -6 / 20)) < 1e-6)
    }
}
