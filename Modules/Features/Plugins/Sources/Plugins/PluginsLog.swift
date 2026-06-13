import Foundation

public enum PluginsLog {
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

    public nonisolated(unsafe) static var minLevel: Level = {
        #if DEBUG
        return .trace
        #else
        return .info
        #endif
    }()

    @inlinable public static func trace(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message(), level: .trace, file: file, function: function, line: line)
    }

    @inlinable public static func debug(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message(), level: .debug, file: file, function: function, line: line)
    }

    @inlinable public static func info(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message(), level: .info, file: file, function: function, line: line)
    }

    @inlinable public static func warning(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message(), level: .warning, file: file, function: function, line: line)
    }

    @inlinable public static func error(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message(), level: .error, file: file, function: function, line: line)
    }

    @usableFromInline static func currentCPUTimeMs() -> Double {
        var spec = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &spec)
        return Double(spec.tv_sec) * 1000.0 + Double(spec.tv_nsec) / 1_000_000.0
    }

    @usableFromInline static func log(_ message: @autoclosure () -> String, level: Level, file: String, function: String, line: Int) {
        guard level >= minLevel else { return }
        let fileName = (file as NSString).lastPathComponent
        let cpuTime = String(format: "%.2f", currentCPUTimeMs())
        print("[\(cpuTime)] [\(fileName):\(line) | \(function)] \(message())")
    }
}
