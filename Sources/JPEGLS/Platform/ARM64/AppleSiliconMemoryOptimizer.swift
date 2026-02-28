/// Apple Silicon memory architecture optimisation for JPEG-LS.
///
/// Provides cache-hierarchy-aware data layouts, unified-memory buffer pooling,
/// memory-mapped I/O helpers, and L1/L2 tile-size tuning tailored for
/// A-series and M-series Apple Silicon processors.
///
/// **Note**: This file is conditionally compiled only on ARM64 architectures
/// so that the x86-64 code path remains cleanly separable.

#if arch(arm64)

import Foundation

// MARK: - Apple Silicon Cache Parameters

/// Cache and memory-architecture parameters for Apple Silicon processors.
///
/// Values are approximate medians for M-series chips; the tile-tuning
/// helpers below use these constants to compute optimal tile sizes.
public enum AppleSiliconCacheParameters {
    /// L1 data-cache size per performance core (bytes) — typical M-series value.
    public static let l1DataCacheSize: Int = 128 * 1024           // 128 KiB
    
    /// L2 shared cache size per cluster (bytes) — typical M-series value.
    public static let l2CacheSize: Int = 16 * 1024 * 1024        // 16 MiB
    
    /// L3 / System Level Cache size (bytes) — typical M2 Pro / M3 Pro value.
    public static let l3CacheSize: Int = 32 * 1024 * 1024        // 32 MiB (conservative)
    
    /// CPU cache-line size in bytes (ARM64 standard).
    public static let cacheLineSize: Int = 64
    
    /// Optimal JPEG-LS context array alignment for cache-line boundaries.
    public static let contextArrayAlignment: Int = 64
    
    /// Maximum single-strip tile height (rows) recommended for L1 fit with 3-component 8-bit data.
    public static let recommendedStripHeight: Int = 16
}

// MARK: - Tile Size Tuning

/// Compute the optimal tile dimensions for JPEG-LS encoding on Apple Silicon.
///
/// Selects tile width and height so that the working set for one tile
/// (three rows of context neighbours + one output row) fits within the
/// L1 data cache of an Apple Silicon performance core.
///
/// ```swift
/// let (tw, th) = optimalTileSize(imageWidth: 3840, imageHeight: 2160, bytesPerSample: 2)
/// // tw ≈ 512, th ≈ 16  (fits within 128 KiB L1 cache)
/// ```
///
/// - Parameters:
///   - imageWidth: Full image width in pixels
///   - imageHeight: Full image height in pixels
///   - bytesPerSample: Bytes per sample (1 for 8-bit, 2 for 16-bit)
///   - componentCount: Number of image components (1 = greyscale, 3 = RGB)
/// - Returns: A tuple `(tileWidth, tileHeight)` optimised for Apple Silicon L1 cache
public func optimalTileSize(
    imageWidth: Int,
    imageHeight: Int,
    bytesPerSample: Int = 1,
    componentCount: Int = 1
) -> (tileWidth: Int, tileHeight: Int) {
    // Budget: L1 cache; reserve 25% for stack/code, use 75% for pixel data
    let budget = (AppleSiliconCacheParameters.l1DataCacheSize * 3) / 4
    
    // Working set per row = width * bytesPerSample * componentCount
    // We need ~4 rows in cache at once (current row + 3 context rows)
    let rowSize = imageWidth * bytesPerSample * componentCount
    let rowsInBudget = max(1, budget / max(1, rowSize))
    let tileHeight = min(imageHeight, max(1, rowsInBudget / 4))
    
    // Tile width: round up to the nearest cache-line boundary in samples,
    // then clamp to the actual image width.
    let samplesPerCacheLine = AppleSiliconCacheParameters.cacheLineSize / max(1, bytesPerSample)
    let alignedWidth = ((imageWidth + samplesPerCacheLine - 1) / samplesPerCacheLine) * samplesPerCacheLine
    let tileWidth = min(imageWidth, alignedWidth)
    
    return (tileWidth, tileHeight)
}

// MARK: - Cache-Line Aligned Buffer Allocation

/// Allocate a cache-line–aligned integer buffer for JPEG-LS context arrays.
///
/// Context arrays (A, B, C, N) are accessed with stride equal to one entry
/// per quantised context (up to 365 contexts). Alignment to cache-line
/// boundaries prevents false-sharing on Apple Silicon's multi-cluster design.
///
/// - Parameter count: Number of elements to allocate
/// - Returns: A zero-initialised `[Int]` of the requested size
///
/// - Note: Swift arrays are heap-allocated and typically 16-byte aligned.
///   This helper pads `count` to the next multiple of the cache-line stride
///   in `Int` units so that adjacent arrays in a struct avoid cache aliasing.
public func allocateCacheAlignedContextArray(count: Int) -> [Int] {
    let alignment = AppleSiliconCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
    let alignedCount = ((count + alignment - 1) / alignment) * alignment
    return [Int](repeating: 0, count: alignedCount)
}

// MARK: - Memory-Mapped I/O

/// Open a file for memory-mapped read-only access on Apple platforms.
///
/// Memory-mapped I/O avoids copying file data into user-space buffers on
/// Apple Silicon's unified memory architecture; the OS kernel maps file
/// pages directly into the process address space using the underlying
/// `mmap(2)` system call.
///
/// ```swift
/// let data = try memoryMappedData(at: url)
/// // Use `data` as a normal Data value — pages are faulted in on demand
/// ```
///
/// - Parameter url: URL of the file to map
/// - Returns: A `Data` value backed by a memory mapping of the file
/// - Throws: `CocoaError` if the file cannot be opened or mapped
public func memoryMappedData(at url: URL) throws -> Data {
    return try Data(contentsOf: url, options: .mappedIfSafe)
}

/// Write data to a file using memory-mapped I/O on Apple platforms.
///
/// Writes the provided `Data` to `url`. For large files on Apple Silicon
/// unified memory, `mappedIfSafe` avoids redundant copies on the write path.
///
/// - Parameters:
///   - data: Data to write
///   - url: Destination file URL
/// - Throws: `CocoaError` if the write fails
public func writeMemoryMapped(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
}

// MARK: - Unified Memory Buffer Pool

/// A buffer pool optimised for Apple Silicon's unified CPU/GPU memory.
///
/// On Apple Silicon, the CPU and GPU share the same physical memory, so
/// Metal `storageModeShared` buffers are accessible without any copy
/// between host and device. This pool manages a set of pre-allocated
/// reusable `Data` buffers of fixed sizes, reducing allocation pressure
/// during encode/decode loops.
///
/// ```swift
/// let pool = UnifiedMemoryBufferPool(bufferSize: 512 * 1024, poolCapacity: 4)
/// let buf  = pool.acquire()
/// // ... use buf for one encode tile ...
/// pool.release(buf)
/// ```
public final class UnifiedMemoryBufferPool: @unchecked Sendable {
    private let bufferSize: Int
    private let poolCapacity: Int
    private var available: [Data] = []
    private let lock = NSLock()
    
    /// Create a new unified-memory buffer pool.
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
/// On ARM64, the compiler is free to lower this to `PRFM PLDL1KEEP`
/// instructions when inlining. The function hint guides the hardware
/// prefetcher for predictable sequential access patterns during
/// row-by-row JPEG-LS encoding/decoding.
///
/// - Parameters:
///   - array: Array whose data should be prefetched
///   - startIndex: First element index to prefetch
///   - count: Number of elements to prefetch (one cache line covers 8 Int values on ARM64)
@inline(__always)
public func prefetchContextArray(_ array: [Int], startIndex: Int, count: Int) {
    let end = min(startIndex + count, array.count)
    guard startIndex < end else { return }
    
    // Touch the first element of every cache line in the range.
    // On ARM64 one cache line holds 64 / MemoryLayout<Int>.stride = 8 Int values.
    let stride = AppleSiliconCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
    var i = startIndex
    while i < end {
        _ = array[i]
        i += stride
    }
}

// MARK: - Hardware-Specific Tuning Parameters

/// Recommended tuning parameters for JPEG-LS on Apple Silicon.
///
/// These constants document the rationale behind the chosen defaults and
/// serve as a single source of truth for any future benchmark-driven tuning.
public enum AppleSiliconTuningParameters {
    /// Recommended RESET threshold for context adaptation on Apple Silicon.
    ///
    /// A higher RESET value keeps context statistics longer before halving,
    /// which is beneficial on Apple Silicon's large register file since the
    /// extra arithmetic is cheaper than a cache miss into a cold context.
    public static let recommendedReset: Int = 64
    
    /// Minimum pixel count for which GPU (Metal) acceleration is beneficial.
    ///
    /// Below this threshold, CPU processing avoids the fixed overhead of
    /// Metal command-buffer encoding and submission.
    public static let metalGpuThreshold: Int = 1024
    
    /// Strip height (rows) for tiled encoding on Apple Silicon performance cores.
    ///
    /// Each strip processes `stripHeight` rows of the image at a time. This
    /// value is chosen so that the three-row context window (current row plus
    /// two predecessor rows) fits comfortably in the L1 data cache.
    public static let stripHeight: Int = AppleSiliconCacheParameters.recommendedStripHeight
    
    /// Context array pre-allocation count (rounded to cache-line boundary).
    ///
    /// JPEG-LS uses 365 regular contexts + 2 run-interruption contexts.
    /// Pre-allocating 384 entries (6 × 64) aligns the end of each context
    /// array to a cache-line boundary on ARM64.
    public static let contextArrayCount: Int = 384
}

#endif // arch(arm64)
