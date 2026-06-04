import Foundation

enum PluginsLog {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static func debug(_ message: String, context: [String: String] = [:]) {
        log(level: .debug, message: message, context: context)
    }

    static func info(_ message: String, context: [String: String] = [:]) {
        log(level: .info, message: message, context: context)
    }

    static func warning(_ message: String, context: [String: String] = [:]) {
        log(level: .warning, message: message, context: context)
    }

    static func error(_ message: String, context: [String: String] = [:]) {
        log(level: .error, message: message, context: context)
    }

    private static func log(level: Level, message: String, context: [String: String]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        if context.isEmpty {
            print("[\(timestamp)] [\(level.rawValue)] [Plugins] \(message)")
        } else {
            let contextString = context
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            print("[\(timestamp)] [\(level.rawValue)] [Plugins] \(message) {\(contextString)}")
        }
    }
}
