//
//  BinaryFloatingPoint+asTimeString.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 04/05/25.
//

import Foundation

public extension BinaryFloatingPoint {
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = style == .positional ? positionalTimeFormatter : makeTimeFormatter(style)
        return formatter.string(from: TimeInterval(self)) ?? ""
    }
}

/// The scrubber formats two times on every 4 Hz tick; building a formatter per call was ~55 ms of
/// main thread per 20 s of playback (Time Profiler, device). Formatters are safe to share once
/// configured.
private nonisolated(unsafe) let positionalTimeFormatter = makeTimeFormatter(.positional)

private func makeTimeFormatter(_ style: DateComponentsFormatter.UnitsStyle) -> DateComponentsFormatter {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = style
    formatter.zeroFormattingBehavior = .pad
    return formatter
}
