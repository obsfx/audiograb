import Foundation

enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    var jsonLabel: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .warn: return "warn"
        case .error: return "error"
        }
    }
}

enum Logger {
    static var minLevel: LogLevel = .info
    static var jsonMode: Bool = false

    static func debug(_ message: String) {
        log(level: .debug, message)
    }

    static func info(_ message: String) {
        log(level: .info, message)
    }

    static func warn(_ message: String) {
        log(level: .warn, message)
    }

    static func error(_ message: String) {
        log(level: .error, message)
    }

    /// Write a raw JSON line to stdout (for non-log event types)
    static func json(_ fields: (String, Any)...) {
        guard jsonMode else { return }
        var dict: [String: Any] = [:]
        for (key, value) in fields {
            dict[key] = value
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           var line = String(data: data, encoding: .utf8) {
            line.append("\n")
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }

    private static func log(level: LogLevel, _ message: String) {
        guard level >= minLevel else { return }

        if jsonMode {
            let dict: [String: Any] = [
                "type": "log",
                "level": level.jsonLabel,
                "message": message,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               var line = String(data: data, encoding: .utf8) {
                line.append("\n")
                FileHandle.standardOutput.write(Data(line.utf8))
            }
        } else {
            let line = "[\(level.label)] \(message)\n"
            if let data = line.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }
}
