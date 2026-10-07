import Foundation

/// A bounded single-producer / single-consumer ring buffer of mono samples.
///
/// ROLE
/// This is the only hand-off between the audio thread and the analysis thread:
///
///     audio callback  →  write()   (producer)
///     analysis worker →  read()    (consumer)
///
/// The audio callback must never run an FFT, allocate, log or touch SwiftUI, so
/// all it does is mix to mono and push samples in here. The analysis worker
/// pulls complete hops out on its own thread.
///
/// DISCARD POLICY
/// When the consumer falls behind, the newest samples win: writing over unwritten
/// data is better than stalling the audio thread, because the buffer exists to
/// serve a live meter, not to archive audio. Every dropped sample is counted in
/// `overflowCount` so the diagnostics panel can report it honestly rather than
/// hiding a problem.
///
/// LOCKING
/// A short `os_unfair_lock` guards the copy and the index update. That is not
/// strictly wait-free, and a purist would want atomics; the critical section is
/// a `memcpy` of at most a few kilobytes with no allocation, no syscall and no
/// nesting, and the measured callback cost is reported in the README. Adding an
/// atomics dependency for this was judged not worth it.
public final class AudioRingBuffer: @unchecked Sendable {

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>

    private var lock = os_unfair_lock_s()
    private var writeIndex = 0
    private var readIndex = 0
    private var storedCount = 0
    private var overflowed = 0

    /// - Parameter capacity: number of mono samples to hold. Rounded up.
    public init(capacity: Int = 16384) {
        self.capacity = max(capacity, 1024)
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        self.storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Total samples discarded because the consumer was too slow.
    public var overflowCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return overflowed
    }

    /// Samples currently readable.
    public var availableCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return storedCount
    }

    /// Writes mono samples. Called from the audio thread.
    ///
    /// Never blocks on the consumer and never grows. If the buffer is full the
    /// oldest data is overwritten.
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        let count = samples.count
        guard count > 0 else { return }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        if count >= capacity {
            // Only the tail can survive.
            let start = count - capacity
            storage.update(from: samples.baseAddress!.advanced(by: start), count: capacity)
            writeIndex = 0
            readIndex = 0
            storedCount = capacity
            overflowed += count - capacity
            return
        }

        let free = capacity - storedCount
        if count > free {
            let dropped = count - free
            // Advance the read cursor past the samples being overwritten.
            readIndex = (readIndex + dropped) % capacity
            storedCount -= dropped
            overflowed += dropped
        }

        let firstChunk = min(count, capacity - writeIndex)
        storage.advanced(by: writeIndex).update(from: samples.baseAddress!, count: firstChunk)
        if firstChunk < count {
            storage.update(
                from: samples.baseAddress!.advanced(by: firstChunk),
                count: count - firstChunk
            )
        }

        writeIndex = (writeIndex + count) % capacity
        storedCount += count
    }

    /// Reads up to `count` samples. Returns how many were actually read.
    ///
    /// Called from the analysis thread only.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let toRead = min(count, storedCount)
        guard toRead > 0 else { return 0 }

        let firstChunk = min(toRead, capacity - readIndex)
        destination.update(from: storage.advanced(by: readIndex), count: firstChunk)
        if firstChunk < toRead {
            destination.advanced(by: firstChunk).update(from: storage, count: toRead - firstChunk)
        }

        readIndex = (readIndex + toRead) % capacity
        storedCount -= toRead
        return toRead
    }

    /// Throws away everything buffered, e.g. when the tap is rebuilt.
    public func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        writeIndex = 0
        readIndex = 0
        storedCount = 0
        storage.update(repeating: 0, count: capacity)
    }
}
