import AudioToolbox
import CoreAudio
import Foundation

final class AudioCaptureSession {
    private let deviceID: AudioObjectID
    private let wavWriter: WAVWriter
    private let ringBuffer = RingBuffer()
    private var ioProcID: AudioDeviceIOProcID?
    private let writerQueue: DispatchQueue
    private var writerTimer: DispatchSourceTimer?
    private let sourceChannels: Int
    private let outputChannels: Int
    private let needsDownmix: Bool

    // Pre-allocated conversion buffer
    private var conversionBuffer: UnsafeMutablePointer<Int16>
    private let conversionBufferCapacity: Int

    // Overflow tracking
    private var lastHighWaterMark: Int = 0

    init(deviceID: AudioObjectID, wavWriter: WAVWriter, sourceChannels: Int, outputChannels: Int) {
        self.deviceID = deviceID
        self.wavWriter = wavWriter
        self.sourceChannels = sourceChannels
        self.outputChannels = outputChannels
        self.needsDownmix = sourceChannels == 2 && outputChannels == 1
        self.writerQueue = DispatchQueue(label: "audiograb.writer", qos: .userInitiated)

        // Pre-allocate conversion buffer: enough for 200ms at 48kHz stereo
        let maxSamples = 48000 * 2 / 5  // 200ms of stereo
        self.conversionBufferCapacity = maxSamples
        self.conversionBuffer = .allocate(capacity: maxSamples)
    }

    deinit {
        conversionBuffer.deallocate()
    }

    func start() throws {
        Logger.debug("Starting capture session")

        var procID: AudioDeviceIOProcID?
        let clientData = Unmanaged.passUnretained(self.ringBuffer).toOpaque()

        let status = AudioDeviceCreateIOProcID(
            deviceID,
            { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData) -> OSStatus in
                guard let clientData = inClientData else { return noErr }
                let ringBuffer = Unmanaged<RingBuffer>.fromOpaque(clientData).takeUnretainedValue()

                let bufferList = inInputData.pointee
                let buf = bufferList.mBuffers

                guard let data = buf.mData, buf.mDataByteSize > 0 else { return noErr }
                _ = ringBuffer.write(data, count: Int(buf.mDataByteSize))

                return noErr
            },
            clientData,
            &procID
        )

        guard status == noErr else {
            Logger.error("AudioDeviceCreateIOProcID failed: \(status)")
            throw AudioCaptureError.ioProcFailed(status)
        }

        self.ioProcID = procID

        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == noErr else {
            if let p = procID {
                AudioDeviceDestroyIOProcID(deviceID, p)
            }
            self.ioProcID = nil
            Logger.error("AudioDeviceStart failed: \(startStatus)")
            throw AudioCaptureError.ioProcFailed(startStatus)
        }

        startWriterTimer()

        Logger.info("Capture session started")
    }

    func stop() {
        Logger.debug("Stopping capture session")

        writerTimer?.cancel()
        writerTimer = nil

        if let procID = ioProcID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            ioProcID = nil
        }

        // Drain remaining data
        drainRingBuffer()

        Logger.debug("Capture session stopped")
    }

    // MARK: - Private

    private func startWriterTimer() {
        let timer = DispatchSource.makeTimerSource(queue: writerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.drainRingBuffer()
        }
        timer.resume()
        writerTimer = timer
    }

    private func drainRingBuffer() {
        let available = ringBuffer.availableBytes
        guard available > 0 else { return }

        let capacity = 4 * 1024 * 1024
        if available > capacity * 3 / 4 && available > lastHighWaterMark {
            Logger.warn("Ring buffer high water: \(available * 100 / capacity)% full")
            lastHighWaterMark = available
        }

        let float32Size = MemoryLayout<Float32>.stride
        // Max bytes to read per iteration (must be frame-aligned)
        let bytesPerSourceFrame = sourceChannels * float32Size
        let maxFrames = conversionBufferCapacity / outputChannels
        let maxReadBytes = maxFrames * bytesPerSourceFrame

        var remaining = available
        let readBuffer = UnsafeMutableRawPointer.allocate(byteCount: maxReadBytes, alignment: 16)
        defer { readBuffer.deallocate() }

        while remaining > 0 {
            // Ensure we read a frame-aligned amount
            let toRead = min(remaining, maxReadBytes)
            let alignedToRead = (toRead / bytesPerSourceFrame) * bytesPerSourceFrame
            guard alignedToRead > 0 else { break }

            let bytesRead = ringBuffer.read(readBuffer, count: alignedToRead)
            guard bytesRead > 0 else { break }

            let frameCount = bytesRead / bytesPerSourceFrame
            let srcPtr = readBuffer.assumingMemoryBound(to: Float32.self)

            if needsDownmix {
                // Stereo -> Mono: average L and R channels
                for f in 0..<frameCount {
                    let left = srcPtr[f * 2]
                    let right = srcPtr[f * 2 + 1]
                    let mono = (left + right) * 0.5
                    let clamped = max(-1.0, min(1.0, mono))
                    conversionBuffer[f] = Int16(clamped * Float32(Int16.max))
                }
                let outBytes = frameCount * MemoryLayout<Int16>.stride
                wavWriter.appendData(conversionBuffer, byteCount: outBytes)
            } else {
                // Pass-through (same channel count): convert Float32 -> Int16
                let sampleCount = frameCount * sourceChannels
                for i in 0..<sampleCount {
                    let clamped = max(-1.0, min(1.0, srcPtr[i]))
                    conversionBuffer[i] = Int16(clamped * Float32(Int16.max))
                }
                let outBytes = sampleCount * MemoryLayout<Int16>.stride
                wavWriter.appendData(conversionBuffer, byteCount: outBytes)
            }

            remaining -= bytesRead
        }
    }
}
