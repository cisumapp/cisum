//
//  PerformanceLogger.swift
//  cisum
//
//  PURPOSE
//  -------
//  Minimal, unified performance logging system for debugging and optimization.
//  Automatically captures file, function, line, and execution time for easy pinpointing.
//
//  USAGE
//  -----
//  import Utilities
//
//  // Simple log with automatic context:
//  PerfLog.trace("Starting operation")
//
//  // Measure execution time:
//  PerfLog.measure("fetch-data") { await fetchData() }
//
//  // Manual timing:
//  let timer = PerfLog.start("complex-operation")
//  defer { PerfLog.end(timer) }
//
//  // Mark significant events:
//  PerfLog.mark("cache-hit")
//

import Foundation
import os.log

/// Minimal performance logger that captures file/function/line and timing.
public enum PerfLog {
    /// Log level for filtering output
    public enum Level: Int, Comparable {
        case trace = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Current minimum log level (defaults to .trace in debug, .info in release)
    public nonisolated(unsafe) static var minLevel: Level = {
        #if DEBUG
        return .trace
        #else
        return .info
        #endif
    }()

    // MARK: - Simple Logging

    /// Log a trace message with automatic file/function/line capture
    @inlinable
    public static func trace(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .trace, file: file, function: function, line: line)
    }

    /// Log a debug message with automatic file/function/line capture
    @inlinable
    public static func debug(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    /// Log an info message with automatic file/function/line capture
    @inlinable
    public static func info(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    /// Log a warning message with automatic file/function/line capture
    @inlinable
    public static func warning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    /// Log an error message with automatic file/function/line capture
    @inlinable
    public static func error(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    // MARK: - Performance Timing

    /// Timer for manual performance measurement
    public struct Timer {
        public let name: String
        public let start: ContinuousClock.Instant
        public let file: String
        public let function: String
        public let line: Int

        public init(name: String, start: ContinuousClock.Instant, file: String, function: String, line: Int) {
            self.name = name
            self.start = start
            self.file = file
            self.function = function
            self.line = line
        }
    }

    /// Start a manual performance timer
    @inlinable
    public static func start(
        _ name: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) -> Timer {
        Timer(
            name: name,
            start: .now,
            file: file,
            function: function,
            line: line
        )
    }

    /// End a manual performance timer and log the duration
    @inlinable
    public static func end(_ timer: Timer) {
        let duration = timer.start.duration(to: .now)
        let ms = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        log(
            "⏱️ \(timer.name) took \(String(format: "%.2f", ms))ms",
            level: .debug,
            file: timer.file,
            function: timer.function,
            line: timer.line
        )
    }

    /// Measure synchronous operation execution time
    @inlinable
    public static func measure<T>(
        _ name: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        operation: () throws -> T
    ) rethrows -> T {
        let start = ContinuousClock.Instant.now
        let result = try operation()
        let duration = start.duration(to: .now)
        let ms = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        log(
            "⏱️ \(name) took \(String(format: "%.2f", ms))ms",
            level: .debug,
            file: file,
            function: function,
            line: line
        )
        return result
    }

    /// Measure asynchronous operation execution time
    @inlinable
    public static func measure<T>(
        _ name: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        operation: () async throws -> T
    ) async rethrows -> T {
        let start = ContinuousClock.Instant.now
        let result = try await operation()
        let duration = start.duration(to: .now)
        let ms = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        log(
            "⏱️ \(name) took \(String(format: "%.2f", ms))ms",
            level: .debug,
            file: file,
            function: function,
            line: line
        )
        return result
    }

    /// Mark a significant event (zero-duration)
    @inlinable
    public static func mark(
        _ name: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log("📍 \(name)", level: .debug, file: file, function: function, line: line)
    }

    // MARK: - Internal Implementation

    @usableFromInline
    static func log(
        _ message: String,
        level: Level,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let icon = levelIcon(level)
        let formatted = "\(icon) [\(fileName):\(line)] \(function) → \(message)"

        // Output to Console.app via unified logging
        switch level {
        case .trace, .debug:
            CisumLog.concurrency.debug("\(formatted, privacy: .public)")
        case .info:
            CisumLog.concurrency.info("\(formatted, privacy: .public)")
        case .warning:
            CisumLog.concurrency.notice("\(formatted, privacy: .public)")
        case .error:
            CisumLog.concurrency.error("\(formatted, privacy: .public)")
        }

        // Also print to Xcode console for immediate visibility
        #if DEBUG
        print(formatted)
        #endif
    }

    @usableFromInline
    static func levelIcon(_ level: Level) -> String {
        switch level {
        case .trace: "🔍"
        case .debug: "🐛"
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        }
    }
}
