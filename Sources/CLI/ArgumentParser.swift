import Foundation

enum AudioSource: String {
    case system
    case mic
}

struct CaptureOptions {
    let outputPath: String
    let duration: Double
    let sampleRate: Int
    let channels: Int
    let source: AudioSource
    let mute: Bool
    let verbose: Bool
    let jsonStdout: Bool
}

enum ArgumentParserError: Error, CustomStringConvertible {
    case missingRequired(String)
    case invalidValue(String, String)
    case unknownOption(String)
    case helpRequested
    case versionRequested

    var description: String {
        switch self {
        case .missingRequired(let name):
            return "Missing required option: \(name)"
        case .invalidValue(let name, let value):
            return "Invalid value '\(value)' for \(name)"
        case .unknownOption(let opt):
            return "Unknown option: \(opt)"
        case .helpRequested, .versionRequested:
            return ""
        }
    }
}

enum ArgumentParser {
    static let version = "1.0.0"

    static func parse(_ args: [String] = Array(CommandLine.arguments.dropFirst())) throws -> CaptureOptions {
        var output: String?
        var duration: Double = 0
        var sampleRate: Int = 48000
        var channels: Int = 2
        var source: AudioSource = .system
        var mute = false
        var verbose = false
        var jsonStdout = false

        var i = 0
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "-h", "--help":
                throw ArgumentParserError.helpRequested
            case "--version":
                throw ArgumentParserError.versionRequested
            case "-o", "--output":
                i += 1
                guard i < args.count else {
                    throw ArgumentParserError.missingRequired("--output")
                }
                output = args[i]
            case "-d", "--duration":
                i += 1
                guard i < args.count, let val = Double(args[i]), val >= 0 else {
                    throw ArgumentParserError.invalidValue("--duration", i < args.count ? args[i] : "")
                }
                duration = val
            case "-r", "--sample-rate":
                i += 1
                guard i < args.count, let val = Int(args[i]), [16000, 44100, 48000].contains(val) else {
                    throw ArgumentParserError.invalidValue("--sample-rate", i < args.count ? args[i] : "")
                }
                sampleRate = val
            case "-c", "--channels":
                i += 1
                guard i < args.count, let val = Int(args[i]), val == 1 || val == 2 else {
                    throw ArgumentParserError.invalidValue("--channels", i < args.count ? args[i] : "")
                }
                channels = val
            case "-s", "--source":
                i += 1
                guard i < args.count, let val = AudioSource(rawValue: args[i]) else {
                    throw ArgumentParserError.invalidValue("--source", i < args.count ? args[i] : "")
                }
                source = val
            case "--mute":
                mute = true
            case "-v", "--verbose":
                verbose = true
            case "--json-stdout":
                jsonStdout = true
            default:
                throw ArgumentParserError.unknownOption(arg)
            }

            i += 1
        }

        guard let outputPath = output else {
            throw ArgumentParserError.missingRequired("--output <path>")
        }

        return CaptureOptions(
            outputPath: outputPath,
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            source: source,
            mute: mute,
            verbose: verbose,
            jsonStdout: jsonStdout
        )
    }

    static func printUsage() {
        let usage = """
        audiograb — macOS system audio capture

        USAGE: audiograb --output <path> [options]

        OPTIONS:
          -o, --output <path>       Output WAV file path (required)
          -d, --duration <seconds>  Recording duration in seconds (0 = until stopped, default: 0)
          -r, --sample-rate <rate>  Sample rate: 16000, 44100, 48000 (default: 48000)
          -c, --channels <count>    Channels: 1 or 2 (default: 2)
          -s, --source <mode>       Audio source: system, mic (default: system)
              --mute                Mute system audio during capture
          -v, --verbose             Verbose logging to stderr
              --json-stdout         Output newline-delimited JSON to stdout
          -h, --help                Show help
              --version             Show version
        """
        FileHandle.standardError.write(Data(usage.utf8))
    }
}
