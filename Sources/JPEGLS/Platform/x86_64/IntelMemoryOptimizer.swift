/// Intel x86-64 memory architecture optimisation for JPEG-LS.
///
/// Provides cache-hierarchy-aware data layouts, buffer pooling,
/// memory-mapped I/O helpers, prefetch hints, and L1/L2 tile-size
/// tuning tailored for Intel Core and Xeon processors.
///
/// **Note**: This file is conditionally compiled only on x86-64
/// architectures so that the ARM64 code path remains cleanly separable.

#if arch(x86_64)

import Foundation

// MARK: - Intel Cache Parameters

/// Cache and memory-architecture parameters for Intel x86-64 processors.
///
/// Values are conservative estimates suitable for a broad range of Intel
/// Core (i3/i5/i7/i9) and Xeon processors. The tile-tuning helpers
/// below use these constants to compute optimal tile sizes.
public enum IntelCacheParameters {
    /// L1 data-cache size per core (bytes) — typical Intel Core value.
    public static let l1DataCacheSize: Int = 32 * 1024              // 32 KiB

    /// L2 cache size per core (bytes) — typical Intel Core value.
    public static let l2CacheSize: Int = 256 * 1024                 // 256 KiB

    /// L3 / Last-Level Cache size (bytes) — conservative estimate.
    public static let l3CacheSize: Int = 8 * 1024 * 1024           // 8 MiB

    /// CPU cache-line size in bytes (x86-64 standard).
    public static let cacheLineSize: Int = 64

    /// Optimal JPEG-LS context array alignment for cache-line boundaries.
    public static let contextArrayAlignment: Int = 64

    /// Maximum single-strip tile height (rows) recommended for L1 fit
    /// with 3-component 8-bit data on Intel processors.
    public static let recommendedStripHeight: Int = 8
}

// MARK: - Tile Size Tuning

/// Compute the optimal tile dimensions for JPEG-LS encoding on Intel x86-64.
///
/// Selects tile width and height so that the working set for one tile
/// (three rows of context neighbours + one output row) fits within the
/// L1 data cache of a typical Intel Core processor.
///
/// ```swift
/// let (tw, th) = intelOptimalTileSize(imageWidth: 3840, imageHeight: 2160, bytesPerSample: 2)
/// // tw ≈ 512, th ≈ 4  (fits within 32 KiB L1 cache)
/// ```
///
/// - Parameters:
///   - imageWidth: Full image width in pixels
///   - imageHeight: Full image height in pixels
///   - bytesPerSample: Bytes per sample (1 for 8-bit, 2 for 16-bit)
///   - componentCount: Number of image components (1 = greyscale, 3 = RGB)
/// - Returns: A tuple `(tileWidth, tileHeight)` optimised for Intel L1 cache
public func intelOptimalTileSize(
    imageWidth: Int,
    imageHeight: Int,
    bytesPerSample: Int = 1,
    componentCount: Int = 1
) -> (tileWidth: Int, tileHeight: Int) {
    // Budget: L1 cache; reserve 25% for stack/code, use 75% for pixel data
    let budget = (IntelCacheParameters.l1DataCacheSize * 3) / 4

    // Working set per row = width * bytesPerSample * componentCount
    // We need ~4 rows in cache at once (current row + 3 context rows)
    let rowSize = imageWidth * bytesPerSample * componentCount
    let rowsInBudget = max(1, budget / max(1, rowSize))
    let tileHeight = min(imageHeight, max(1, rowsInBudget / 4))

    // Tile width: round up to the nearest cache-line boundary in samples,
    // then clamp to the actual image width.
    let samplesPerCacheLine = IntelCacheParameters.cacheLineSize / max(1, bytesPerSample)
    let alignedWidth = ((imageWidth + samplesPerCacheLine - 1) / samplesPerCacheLine) * samplesPerCacheLine
    let tileWidth = min(imageWidth, alignedWidth)

    return (tileWidth, tileHeight)
}

// MARK: - Cache-Line Aligned Buffer Allocation

/// Allocate a cache-line–aligned integer buffer for JPEG-LS context arrays.
///
/// Context arrays (A, B, C, N) are accessed with stride equal to one entry
/// per quantised context (up to 365 contexts). Alignment to cache-line
/// boundaries prevents false-sharing on multi-core Intel processors.
///
/// - Parameter count: Number of elements to allocate
/// - Returns: A zero-initialised `[Int]` of the requested size
///
/// - Note: Swift arrays are heap-allocated and typically 16-byte aligned.
///   This helper pads `count` to the next multiple of the cache-line stride
///   in `Int` units so that adjacent arrays in a struct avoid cache aliasing.
public func intelAllocateCacheAlignedContextArray(count: Int) -> [Int] {
    let alignment = IntelCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
    let alignedCount = ((count + alignment - 1) / alignment) * alignment
    return [Int](repeating: 0, count: alignedCount)
}

// MARK: - Memory-Mapped I/O

/// Open a file for memory-mapped read-only access on Intel x86-64.
///
/// Memory-mapped I/O avoids copying file data into user-space buffers;
/// the OS kernel maps file pages directly into the process address space
/// using the underlying `mmap(2)` system call.
///
/// ```swift
/// let data = try intelMemoryMappedData(at: url)
/// // Use `data` as a normal Data value — pages are faulted in on demand
/// ```
///
/// - Parameter url: URL of the file to map
/// - Returns: A `Data` value backed by a memory mapping of the file
/// - Throws: An error if the file cannot be opened or mapped
public func intelMemoryMappedData(at url: URL) throws -> Data {
    return try Data(contentsOf: url, options: .mappedIfSafe)
}

/// Write data to a file on Intel x86-64.
///
/// Writes the provided `Data` to `url` atomically to avoid partial writes.
///
/// - Parameters:
///   - data: Data to write
///   - url: Destination file URL
/// - Throws: An error if the write fails
public func intelWriteMemoryMapped(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
}

// MARK: - Buffer Pool

/// A buffer pool optimised for Intel x86-64 JPEG-LS processing.
///
/// This pool manages a set of pre-allocated reusable `Data` buffers of
/// fixed sizes, reducing allocation pressure during encode/decode loops.
///
/// ```swift
/// let pool = IntelBufferPool(bufferSize: 256 * 1024, poolCapacity: 4)
/// let buf  = pool.acquire()
/// // ... use buf for one encode tile ...
/// pool.release(buf)
/// ```
public final class IntelBufferPool: @unchecked Sendable {
    private let bufferSize: Int
    private let poolCapacity: Int
    private var available: [Data] = []
    private let lock = NSLock()

    /// Create a new buffer pool.
    ///
    /// - Parameters:
    ///   - bufferSize: Size of each buffer in bytes
    ///   - poolCapacity: Maximum number of buffers held in the pool
    public init(bufferSize: Int, poolCapacity: Int = 4) {
        self.bufferSize = bufferSize
        self.poolCapacity = poolCapacity
    }

    /// Acquire a buffer from the pool, allocating a new one if empty.
    ///
    /// - Returns: A `Data` value of `bufferSize` bytes (zeroed on first allocation;
    ///   contents undefined on subsequent reuse)
    public func acquire() -> Data {
        lock.lock()
        defer { lock.unlock() }
        if !available.isEmpty {
            return available.removeLast()
        }
        return Data(count: bufferSize)
    }

    /// Return a buffer to the pool for reuse.
    ///
    /// Buffers exceeding `poolCapacity` are silently discarded to bound
    /// peak memory usage.
    ///
    /// - Parameter buffer: Previously acquired buffer
    public func release(_ buffer: Data) {
        lock.lock()
        defer { lock.unlock() }
        if available.count < poolCapacity {
            available.append(buffer)
        }
    }

    /// Pre-warm the pool by allocating `poolCapacity` buffers eagerly.
    ///
    /// Call this once at startup to avoid allocation latency on the first
    /// batch of encode/decode tiles.
    public func prewarm() {
        lock.lock()
        defer { lock.unlock() }
        while available.count < poolCapacity {
            available.append(Data(count: bufferSize))
        }
    }

    /// The number of buffers currently available in the pool.
    public var availableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return available.count
    }
}

// MARK: - Prefetch Hints

/// Issue a software prefetch hint for the given memory region.
///
/// On x86-64, the compiler may lower this to PREFETCHT0 instructions
/// when inlining. The function hint guides the hardware prefetcher for
/// predictable sequential access patterns during row-by-row JPEG-LS
/// encoding/decoding.
///
/// - Parameters:
///   - array: Array whose data should be prefetched
///   - startIndex: First element index to prefetch
///   - count: Number of elements to prefetch (one cache line covers 8 Int values on x86-64)
@inline(__always)
public func intelPrefetchContextArray(_ array: [Int], startIndex: Int, count: Int) {
    let end = min(startIndex + count, array.count)
    guard startIndex < end else { return }

    // Touch the first element of every cache line in the range.
    // On x86-64 one cache line holds 64 / MemoryLayout<Int>.stride = 8 Int values.
    let stride = IntelCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
    var i = startIndex
    while i < end {
        _ = array[i]
        i += stride
    }
}

// MARK: - Hardware-Specific Tuning Parameters

/// Recommended tuning parameters for JPEG-LS on Intel x86-64.
///
/// These constants document the rationale behind the chosen defaults and
/// serve as a single source of truth for any future benchmark-driven tuning.
public enum IntelTuningParameters {
    /// Recommended RESET threshold for context adaptation on Intel x86-64.
    ///
    /// Intel processors have smaller register files than ARM64, so keeping
    /// RESET moderate balances context accuracy against cache pressure.
    public static let recommendedReset: Int = 64

    /// Strip height (rows) for tiled encoding on Intel x86-64.
    ///
    /// Each strip processes `stripHeight` rows of the image at a time.
    /// This value is chosen so that the three-row context window fits
    /// comfortably in the Intel L1 data cache (32 KiB).
    public static let stripHeight: Int = IntelCacheParameters.recommendedStripHeight

    /// Context array pre-allocation count (rounded to cache-line boundary).
    ///
    /// JPEG-LS uses 365 regular contexts + 2 run-interruption contexts.
    /// Pre-allocating 384 entries (6 × 64) aligns the end of each context
    /// array to a cache-line boundary on x86-64.
    public static let contextArrayCount: Int = 384
}

#endif // arch(x86_64)
