//
//  Equalizer.swift
//  PlaybackCore
//
//  A ten-band equalizer run inside AVPlayer through an audio processing tap.
//

import Accelerate
import AVFoundation
import MediaToolbox
import os
import Utilities

/// Ten peaking filters at the usual octave centres, plus a preamp that keeps a boost from clipping.
///
/// AVPlayer has no equalizer of its own, but it hands each item's decoded audio to an
/// `MTAudioProcessingTap` before output, which is where this runs. A tap needs the item's audio
/// track, so it works on progressive files (what ranking prefers) and not on HLS manifests.
///
/// One instance, because there is one audio output: settings change here and every tap — both of
/// the engine's decks — reads them on its next render.
public final class Equalizer: @unchecked Sendable {
    public static let shared = Equalizer()

    /// Band centres in Hz.
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// The gain each band can take, in dB.
    public static let gainRange: ClosedRange<Float> = -12 ... 12

    private struct State {
        var isEnabled = false
        var gains = [Float](repeating: 0, count: Equalizer.frequencies.count)
        /// One filter per sample rate a tap has been prepared for. Built off the render thread.
        var filters: [Double: Filter] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Applies new settings. Every tap picks them up on its next render.
    public func update(isEnabled: Bool, gains: [Float]) {
        let rates = state.withLock { state in
            state.isEnabled = isEnabled
            state.gains = gains
            return Array(state.filters.keys)
        }
        let built = rates.map { ($0, Filter(gains: gains, sampleRate: $0)) }
        state.withLock { $0.filters.merge(built) { $1 } }
    }

    /// Builds the filter for a sample rate, if no tap has needed one yet. Called from a tap's
    /// prepare, which is allowed to allocate; rendering is not.
    fileprivate func prepare(sampleRate: Double) {
        guard let gains = state.withLock({ $0.filters[sampleRate] == nil ? $0.gains : nil }) else { return }
        let filter = Filter(gains: gains, sampleRate: sampleRate)
        state.withLock { $0.filters[sampleRate] = filter }
    }

    /// The filter to render with, or `nil` to pass audio through. Never waits: if settings are being
    /// written at that instant, this render passes through rather than blocking the audio thread.
    fileprivate func filter(for sampleRate: Double) -> Filter? {
        state.withLockIfAvailable { $0.isEnabled ? $0.filters[sampleRate] : nil } ?? nil
    }

    // MARK: - Attaching

    /// Puts a tap on the item's audio track. Without one (an HLS item), the item plays unequalized.
    @MainActor
    public func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
              let tap = Self.makeTap()
        else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }

    private static func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { _, _, storage in
                storage.pointee = Unmanaged.passRetained(TapContext()).toOpaque()
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                TapContext.of(tap).prepare(format.pointee)
            },
            unprepare: { tap in
                TapContext.of(tap).unprepare()
            },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                TapContext.of(tap).process(buffers, frames: framesOut.pointee)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }

    // MARK: - Filters

    /// RBJ cookbook peaking filter, in the order `vDSP_biquad` takes: b0, b1, b2, a1, a2 over a0.
    static func peaking(gain: Float, frequency: Double, sampleRate: Double, q: Double = 1.41) -> [Double] {
        let a = pow(10, Double(gain) / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha / a
        return [1 + alpha * a, -2 * cos(w0), 1 - alpha * a, -2 * cos(w0), 1 - alpha / a].map { $0 / a0 }
    }

    /// The cascade for one set of gains at one sample rate. Immutable once built, so taps on any
    /// thread can share it.
    final class Filter: @unchecked Sendable {
        let setup: vDSP_biquad_Setup?
        let preamp: Float

        init(gains: [Float], sampleRate: Double) {
            // Flat bands, and bands at or above Nyquist, are left out of the cascade.
            let coefficients = zip(gains, Equalizer.frequencies)
                .filter { $0.0 != 0 && $0.1 < sampleRate / 2 }
                .flatMap { Equalizer.peaking(gain: $0.0, frequency: $0.1, sampleRate: sampleRate) }
            setup = coefficients.isEmpty ? nil : vDSP_biquad_CreateSetup(coefficients, vDSP_Length(coefficients.count / 5))
            // Turned down by the largest boost, so a boosted band cannot push the signal past full scale.
            preamp = pow(10, -max(gains.max() ?? 0, 0) / 20)
        }

        deinit {
            if let setup { vDSP_biquad_DestroySetup(setup) }
        }

        func apply(_ samples: UnsafeMutablePointer<Float>, count: vDSP_Length, delay: UnsafeMutablePointer<Float>) {
            if let setup {
                vDSP_biquad(setup, delay, samples, 1, samples, 1, count)
            }
            if preamp != 1 {
                var gain = preamp
                vDSP_vsmul(samples, 1, &gain, samples, 1, count)
            }
        }
    }
}

/// One tap's own state: its format and each channel's filter memory.
private final class TapContext {
    /// Delay elements per channel: `vDSP_biquad` needs 2 × sections + 2.
    static let delayStride = 2 * Equalizer.frequencies.count + 2

    var sampleRate: Double = 0
    var channels = 0
    var delays: UnsafeMutablePointer<Float>?

    static func of(_ tap: MTAudioProcessingTap) -> TapContext {
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        unprepare()
        // AVPlayer hands taps non-interleaved Float32; anything else passes through untouched.
        let flags = format.mFormatFlags
        guard flags & kAudioFormatFlagIsFloat != 0, flags & kAudioFormatFlagIsNonInterleaved != 0,
              format.mBitsPerChannel == 32
        else { return }
        sampleRate = format.mSampleRate
        channels = Int(format.mChannelsPerFrame)
        let count = channels * Self.delayStride
        delays = .allocate(capacity: count)
        delays?.initialize(repeating: 0, count: count)
        Equalizer.shared.prepare(sampleRate: sampleRate)
        PerfLog.info("Equalizer tap ready: \(Int(sampleRate)) Hz, \(channels) channel(s)")
    }

    func unprepare() {
        delays?.deallocate()
        delays = nil
        channels = 0
    }

    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        // ponytail: a filter released here when settings changed mid-render is freed on the audio
        // thread; rare and brief. Hand releases to a queue if it ever glitches.
        guard let delays, let filter = Equalizer.shared.filter(for: sampleRate) else { return }
        for (channel, buffer) in UnsafeMutableAudioBufferListPointer(buffers).enumerated() where channel < channels {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            filter.apply(samples, count: vDSP_Length(frames), delay: delays + channel * Self.delayStride)
        }
    }
}
