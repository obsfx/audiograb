import Darwin
import Foundation

/// Lock-free single-producer single-consumer ring buffer.
/// Producer: real-time IOProc thread (writes raw Float32 audio).
/// Consumer: background writer queue (reads and converts to Int16).
///
/// Thread safety: Uses separate head (write) and tail (read) pointers.
/// Only the producer writes to head, only the consumer writes to tail.
/// Memory ordering is ensured by OSMemoryBarrier.
final class RingBuffer {
    private let capacity: Int
    private let buffer: UnsafeMutableRawPointer

    // Head = total bytes written (only modified by producer)
    // Tail = total bytes read (only modified by consumer)
    // Available = head - tail
    private var head: UInt64 = 0
    private var tail: UInt64 = 0

    var availableBytes: Int {
        return Int(head - tail)
    }

    var freeBytes: Int {
        return capacity - availableBytes
    }

    init(capacity: Int = 4 * 1024 * 1024) {
        self.capacity = capacity
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        self.buffer.initializeMemory(as: UInt8.self, repeating: 0, count: capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// Write bytes into the ring buffer. Called from the real-time audio thread.
    /// Returns the number of bytes actually written (< count means overflow).
    @discardableResult
    func write(_ src: UnsafeRawPointer, count: Int) -> Int {
        let free = freeBytes
        let toWrite = min(count, free)
        guard toWrite > 0 else { return 0 }

        let writePos = Int(head % UInt64(capacity))
        let firstChunk = min(toWrite, capacity - writePos)

        buffer.advanced(by: writePos).copyMemory(from: src, byteCount: firstChunk)

        if firstChunk < toWrite {
            let secondChunk = toWrite - firstChunk
            buffer.copyMemory(from: src.advanced(by: firstChunk), byteCount: secondChunk)
        }

        OSMemoryBarrier()
        head += UInt64(toWrite)
        return toWrite
    }

    /// Read bytes from the ring buffer into a destination pointer.
    /// Returns the number of bytes actually read.
    @discardableResult
    func read(_ dst: UnsafeMutableRawPointer, count: Int) -> Int {
        let available = availableBytes
        let toRead = min(count, available)
        guard toRead > 0 else { return 0 }

        let readPos = Int(tail % UInt64(capacity))
        let firstChunk = min(toRead, capacity - readPos)

        dst.copyMemory(from: buffer.advanced(by: readPos), byteCount: firstChunk)

        if firstChunk < toRead {
            let secondChunk = toRead - firstChunk
            dst.advanced(by: firstChunk).copyMemory(from: buffer, byteCount: secondChunk)
        }

        OSMemoryBarrier()
        tail += UInt64(toRead)
        return toRead
    }
}
