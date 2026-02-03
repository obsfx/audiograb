import Foundation

enum ExitCode: Int32 {
    case success = 0
    case permissionDenied = 1
    case deviceError = 2
    case fileIOError = 3
    case invalidArgs = 4
    case unexpected = 5

    var message: String {
        switch self {
        case .success:
            return "Recording completed successfully"
        case .permissionDenied:
            return "Permission denied: System audio recording requires authorization. Open System Settings > Privacy & Security > Screen & System Audio Recording"
        case .deviceError:
            return "Audio device error: Failed to create or configure the audio tap device"
        case .fileIOError:
            return "File I/O error: Failed to create or write to the output file"
        case .invalidArgs:
            return "Invalid arguments"
        case .unexpected:
            return "Unexpected error occurred"
        }
    }
}

func exitWithCode(_ code: ExitCode, detail: String? = nil) -> Never {
    if code != .success {
        var msg = "Error: \(code.message)"
        if let detail = detail {
            msg += " — \(detail)"
        }
        Logger.error(msg)
    }
    exit(code.rawValue)
}
