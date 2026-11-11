//
//  VinylSpin.swift
//  Aesthetics
//
//  The physics of a spinning record: angle, angular velocity, and the exponential
//  acceleration curve that spins a platter up and lets it coast down.
//
//  Extracted from `Vinyl` so the full-screen hero player and the macOS backdrop cannot drift
//  apart — they are the same record, so they must turn the same way.
//

import Foundation
import Observation

@MainActor
@Observable
final class VinylSpin {
    /// Whether the record is still turning. Feeds `TimelineView(.animation(paused:))`: a parked
    /// record needs no clock. Left running, the paused full player re-rendered the disc every
    /// frame — ~1.3 s of main-thread work per 20 s with nothing moving (Time Profiler, device).
    private(set) var isTurning = false
    private(set) var phaseStartAngle: Double = 0
    private var phaseStartDate: Date?
    private var phaseStartSpeed: Double = 0
    private var phaseTargetSpeed: Double = 0
    private var phaseTau: Double = 0.67

    private let targetMaxSpeed: Double = 35
    private let tauStart: Double = 0.6
    private let tauStop: Double = 0.67

    /// Current angle in degrees. Pure function of the timestamp, so a caller inside a
    /// `TimelineView` can ask every frame without any stored per-frame state.
    func rotation(at date: Date) -> Double {
        guard let phaseStartDate else {
            return phaseStartAngle
        }

        let elapsed = max(date.timeIntervalSince(phaseStartDate), 0)
        let deltaSpeed = phaseStartSpeed - phaseTargetSpeed

        // Fast path once acceleration settles to steady-state motion.
        if abs(deltaSpeed) < 0.0001 {
            return phaseStartAngle + (phaseTargetSpeed * elapsed)
        }

        return phaseStartAngle + (phaseTargetSpeed * elapsed)
            + (deltaSpeed * phaseTau * (1 - exp(-elapsed / phaseTau)))
    }

    private func speed(at date: Date) -> Double {
        guard let phaseStartDate else { return 0 }
        let elapsed = max(date.timeIntervalSince(phaseStartDate), 0)
        let delta = phaseStartSpeed - phaseTargetSpeed
        if abs(delta) < 0.0001 {
            return phaseTargetSpeed
        }
        return phaseTargetSpeed + delta * exp(-elapsed / phaseTau)
    }

    /// Re-bases the phase onto `date` so the angle and velocity are continuous across a
    /// play/pause change — the record eases into or out of its new speed instead of jumping.
    func syncPlaybackState(at date: Date, isPlaying: Bool) {
        let currentAngle = rotation(at: date)
        let currentSpeed = speed(at: date)
        let nextTargetSpeed = isPlaying ? targetMaxSpeed : 0
        let nextTau = isPlaying ? tauStart : tauStop

        phaseStartAngle = currentAngle
        phaseStartDate = date
        phaseStartSpeed = currentSpeed
        phaseTargetSpeed = nextTargetSpeed
        phaseTau = nextTau
    }

    /// Run from `.task(id: isPlaying)`. Playing starts the clock at once; pausing stops it after the
    /// coast-down, ~6τ, when the platter is under 0.1°/s and the last bit of travel is invisible.
    func settle(isPlaying: Bool) async {
        if isPlaying {
            isTurning = true
            return
        }
        try? await Task.sleep(for: .seconds(tauStop * 6))
        if !Task.isCancelled { isTurning = false }
    }
}
