import Foundation

public enum Logger {
    private static let logFileURL: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("cisum_logs.txt")
    }()
    
    private static let queue = DispatchQueue(label: "com.cisum.logger", qos: .utility)
    
    // Limits log file to ~1MB
    private static let maxLogFileSize: UInt64 = 1024 * 1024

    /// Writes normal debug logs to the console only, keeping the log file clean.
    public nonisolated static func log(_ message: String) {
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #else
        let platform = "Apple"
        #endif

        print("[\(platform)-DEBUG] \(message)")
    }
    
    /// Writes errors to both the console AND the persistent log file.
    public nonisolated static func error(_ message: String) {
        log("ERROR: \(message)")
        writeToFile("[ERROR] [\(Date().ISO8601Format())] \(message)\n")
    }
    
    private nonisolated static func writeToFile(_ text: String) {
        queue.async {
            guard let data = text.data(using: .utf8) else { return }
            
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                // Truncate if too large
                if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
                   let fileSize = attributes[.size] as? UInt64,
                   fileSize > maxLogFileSize {
                    try? data.write(to: logFileURL) // Overwrite
                    return
                }
                
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    public static func getLogFileURL() -> URL {
        return logFileURL
    }
    
    // MARK: - Crash Reporting
    
    /// Sets up basic native crash reporting to catch fatal errors and unhandled exceptions.
    public static func initCrashReporter() {
        // Handle standard Swift / ObjC exceptions
        NSSetUncaughtExceptionHandler(cisum_exception_handler)
        
        // Handle signals (e.g. forced unwraps, memory corruption)
        signal(SIGABRT, cisum_signal_handler)
        signal(SIGILL, cisum_signal_handler)
        signal(SIGSEGV, cisum_signal_handler)
        signal(SIGFPE, cisum_signal_handler)
        signal(SIGBUS, cisum_signal_handler)
        signal(SIGPIPE, cisum_signal_handler)
    }
    
    fileprivate static func writeSignalCrash(sig: Int32) {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        let crashLog = """
        
        ================ FATAL SIGNAL ================
        Date: \(Date().ISO8601Format())
        Signal: \(sig)

        
        Stack Trace:
        \(stack)
        ==============================================
        
        """
        
        if let data = crashLog.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logFileURL)
            }
        }
        
        // Exit normally to allow system to generate its own report too if needed
        exit(1)
    }
    
    fileprivate static func writeExceptionCrash(exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        let crashLog = """
        
        ================ CRASH REPORT ================
        Date: \(Date().ISO8601Format())
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        
        Stack Trace:
        \(stack)
        ==============================================
        
        """
        
        if let data = crashLog.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}

private func cisum_signal_handler(signal: Int32) {
    Logger.writeSignalCrash(sig: signal)
}

private func cisum_exception_handler(exception: NSException) {
    Logger.writeExceptionCrash(exception: exception)
}
