import Foundation

final class WAVWriter {
    private let fileHandle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private let bitsPerSample: UInt16 = 16
    private(set) var dataSize: UInt32 = 0

    init(path: String, sampleRate: UInt32, channels: UInt16) throws {
        // Create the file
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw WAVError.cannotCreateFile(path)
        }

        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw WAVError.cannotOpenFile(path)
        }

        self.fileHandle = handle
        self.sampleRate = sampleRate
        self.channels = channels

        // Write placeholder header (44 bytes)
        writeHeader(dataSize: 0)

        Logger.debug("WAV writer initialized: \(path) (\(sampleRate)Hz, \(channels)ch, \(bitsPerSample)-bit)")
    }

    /// Append interleaved Int16 PCM samples.
    func appendData(_ data: UnsafeRawPointer, byteCount: Int) {
        let bufferPointer = UnsafeRawBufferPointer(start: data, count: byteCount)
        fileHandle.write(Data(bufferPointer))
        dataSize += UInt32(byteCount)
    }

    /// Append Data containing interleaved Int16 PCM samples.
    func appendData(_ data: Data) {
        fileHandle.write(data)
        dataSize += UInt32(data.count)
    }

    /// Seek back and write correct chunk sizes into the WAV header.
    func finalize() {
        // RIFF chunk size at offset 4: fileSize - 8
        let riffChunkSize = UInt32(36 + dataSize)
        fileHandle.seek(toFileOffset: 4)
        writeUInt32(riffChunkSize)

        // data subchunk size at offset 40
        fileHandle.seek(toFileOffset: 40)
        writeUInt32(dataSize)

        fileHandle.closeFile()
        Logger.info("WAV finalized: \(dataSize) bytes of PCM data")
    }

    // MARK: - Private

    private func writeHeader(dataSize: UInt32) {
        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)                             // ChunkID
        appendUInt32(to: &header, value: 36 + dataSize)                    // ChunkSize
        header.append(contentsOf: "WAVE".utf8)                             // Format

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)                             // Subchunk1ID
        appendUInt32(to: &header, value: 16)                               // Subchunk1Size (PCM)
        appendUInt16(to: &header, value: 1)                                // AudioFormat (1 = PCM)
        appendUInt16(to: &header, value: channels)                         // NumChannels
        appendUInt32(to: &header, value: sampleRate)                       // SampleRate
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        appendUInt32(to: &header, value: byteRate)                         // ByteRate
        let blockAlign = channels * (bitsPerSample / 8)
        appendUInt16(to: &header, value: blockAlign)                       // BlockAlign
        appendUInt16(to: &header, value: bitsPerSample)                    // BitsPerSample

        // data subchunk
        header.append(contentsOf: "data".utf8)                             // Subchunk2ID
        appendUInt32(to: &header, value: dataSize)                         // Subchunk2Size

        fileHandle.write(header)
    }

    private func appendUInt16(to data: inout Data, value: UInt16) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: 2))
    }

    private func appendUInt32(to data: inout Data, value: UInt32) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: 4))
    }

    private func writeUInt32(_ value: UInt32) {
        var le = value.littleEndian
        fileHandle.write(Data(bytes: &le, count: 4))
    }
}

enum WAVError: Error, CustomStringConvertible {
    case cannotCreateFile(String)
    case cannotOpenFile(String)

    var description: String {
        switch self {
        case .cannotCreateFile(let path):
            return "Cannot create file: \(path)"
        case .cannotOpenFile(let path):
            return "Cannot open file for writing: \(path)"
        }
    }
}
