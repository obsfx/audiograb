import AudioToolbox
import CoreAudio
import Foundation

// Parse arguments
do {
    let options = try ArgumentParser.parse()

    if options.verbose {
        Logger.minLevel = .debug
    }
    if options.jsonStdout {
        Logger.jsonMode = true
    }

    Logger.info("audiograb v\(ArgumentParser.version)")
    Logger.debug("Output: \(options.outputPath)")
    Logger.debug("Duration: \(options.duration > 0 ? "\(options.duration)s" : "unlimited")")
    Logger.debug("Sample rate: \(options.sampleRate) Hz")
    Logger.debug("Channels: \(options.channels)")
    Logger.debug("Mute: \(options.mute)")

    // Validate output path is writable
    let outputURL = URL(fileURLWithPath: options.outputPath)
    let directory = outputURL.deletingLastPathComponent().path
    guard FileManager.default.isWritableFile(atPath: directory) else {
        exitWithCode(.fileIOError, detail: "Directory not writable: \(directory)")
    }

    // Set up audio tap first to get the native format
    let tapManager = AudioTapManager()
    do {
        try tapManager.setup(mute: options.mute)
    } catch AudioCaptureError.permissionDenied {
        exitWithCode(.permissionDenied)
    } catch {
        exitWithCode(.deviceError, detail: error.localizedDescription)
    }

    guard let deviceID = tapManager.aggregateDeviceID,
          let tapFormat = tapManager.tapFormat else {
        exitWithCode(.deviceError, detail: "No aggregate device created")
    }

    // Use tap's native sample rate; channel count from user option (downmix supported)
    let outputSampleRate = UInt32(tapFormat.mSampleRate)
    let outputChannels = UInt16(options.channels)
    let sourceChannels = Int(tapFormat.mChannelsPerFrame)

    if Int(outputSampleRate) != options.sampleRate {
        Logger.info("Using tap native sample rate: \(outputSampleRate) Hz (requested \(options.sampleRate) Hz)")
    }

    // Initialize WAV writer with actual output format
    let wavWriter: WAVWriter
    do {
        wavWriter = try WAVWriter(
            path: options.outputPath,
            sampleRate: outputSampleRate,
            channels: outputChannels
        )
    } catch {
        exitWithCode(.fileIOError, detail: error.localizedDescription)
    }

    // Set up capture session
    let session = AudioCaptureSession(
        deviceID: deviceID,
        wavWriter: wavWriter,
        sourceChannels: sourceChannels,
        outputChannels: Int(outputChannels)
    )

    // Cleanup closure shared by signal handler and duration timer
    let startTime = CFAbsoluteTimeGetCurrent()
    let cleanup: () -> Void = {
        if !Logger.jsonMode {
            FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        }
        session.stop()
        wavWriter.finalize()
        tapManager.teardown()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger.info("Recorded \(String(format: "%.1f", elapsed))s to \(options.outputPath)")
        Logger.json(
            ("type", "result"),
            ("path", options.outputPath),
            ("duration", round(elapsed * 10) / 10)
        )
    }

    // Install signal handlers for graceful shutdown
    SignalHandler.install {
        Logger.info("Signal received, stopping...")
        cleanup()
        exit(ExitCode.success.rawValue)
    }

    // Set up duration timer if specified
    var durationTimer: DispatchSourceTimer?
    if options.duration > 0 {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + options.duration)
        timer.setEventHandler {
            Logger.info("Duration reached (\(options.duration)s), stopping...")
            cleanup()
            exit(ExitCode.success.rawValue)
        }
        timer.resume()
        durationTimer = timer
    }
    _ = durationTimer  // prevent unused variable warning

    // Start capture
    do {
        try session.start()
    } catch {
        exitWithCode(.deviceError, detail: error.localizedDescription)
    }

    // Live elapsed time display
    let displayTimer = DispatchSource.makeTimerSource(queue: .main)
    displayTimer.schedule(deadline: .now(), repeating: 1.0)
    displayTimer.setEventHandler {
        let elapsed = Int(CFAbsoluteTimeGetCurrent() - startTime)
        let m = elapsed / 60
        let s = elapsed % 60
        let timeStr = String(format: "%02d:%02d", m, s)
        if Logger.jsonMode {
            Logger.json(
                ("type", "duration"),
                ("elapsed", elapsed),
                ("formatted", timeStr)
            )
        } else {
            if options.duration > 0 {
                FileHandle.standardError.write(Data("\r\u{1B}[K[INFO] Recording \(timeStr) / \(Int(options.duration))s (press Ctrl+C to stop)".utf8))
            } else {
                FileHandle.standardError.write(Data("\r\u{1B}[K[INFO] Recording \(timeStr) (press Ctrl+C to stop)".utf8))
            }
        }
    }
    displayTimer.resume()
    _ = displayTimer

    // dispatchMain() services both GCD main queue and CFRunLoop — never returns
    dispatchMain()

} catch ArgumentParserError.helpRequested {
    ArgumentParser.printUsage()
    exit(ExitCode.success.rawValue)
} catch ArgumentParserError.versionRequested {
    FileHandle.standardError.write(Data("audiograb \(ArgumentParser.version)\n".utf8))
    exit(ExitCode.success.rawValue)
} catch let error as ArgumentParserError {
    Logger.error(error.description)
    ArgumentParser.printUsage()
    exit(ExitCode.invalidArgs.rawValue)
} catch {
    Logger.error("Unexpected error: \(error.localizedDescription)")
    exit(ExitCode.unexpected.rawValue)
}
