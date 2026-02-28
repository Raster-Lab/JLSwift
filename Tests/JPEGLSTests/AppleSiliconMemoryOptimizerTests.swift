/// Tests for Phase 13.3 Apple Silicon memory architecture optimisation.
///
/// These tests verify the tile-size tuning, cache-aligned buffer allocation,
/// unified-memory buffer pool, and prefetch helpers added in
/// `AppleSiliconMemoryOptimizer.swift` as part of Milestone 13 Phase 13.3.
///
/// All tests are compiled and run only on ARM64 architectures.

#if arch(arm64)

import Testing
import Foundation
@testable import JPEGLS

@Suite("Apple Silicon Memory Optimizer Tests")
struct AppleSiliconMemoryOptimizerTests {

    // MARK: - Cache Parameters

    @Test("L1 cache size is a positive power of two")
    func l1CacheSizePositive() {
        let size = AppleSiliconCacheParameters.l1DataCacheSize
        #expect(size > 0)
        #expect((size & (size - 1)) == 0, "L1 cache size should be a power of two")
    }

    @Test("Cache line size is 64 bytes on ARM64")
    func cacheLineSizeIs64() {
        #expect(AppleSiliconCacheParameters.cacheLineSize == 64)
    }

    @Test("L2 cache is larger than L1")
    func l2LargerThanL1() {
        #expect(AppleSiliconCacheParameters.l2CacheSize > AppleSiliconCacheParameters.l1DataCacheSize)
    }

    @Test("L3 cache is larger than L2")
    func l3LargerThanL2() {
        #expect(AppleSiliconCacheParameters.l3CacheSize > AppleSiliconCacheParameters.l2CacheSize)
    }

    // MARK: - Tile Size Tuning

    @Test("optimalTileSize returns positive dimensions")
    func tileSizePositive() {
        let (tw, th) = optimalTileSize(imageWidth: 1920, imageHeight: 1080, bytesPerSample: 1)
        #expect(tw > 0)
        #expect(th > 0)
    }

    @Test("optimalTileSize width does not exceed image width")
    func tileSizeWidthBounded() {
        let (tw, _) = optimalTileSize(imageWidth: 100, imageHeight: 100, bytesPerSample: 1)
        #expect(tw <= 100)
    }

    @Test("optimalTileSize height does not exceed image height")
    func tileSizeHeightBounded() {
        let (_, th) = optimalTileSize(imageWidth: 1920, imageHeight: 4, bytesPerSample: 1)
        #expect(th <= 4)
    }

    @Test("optimalTileSize for 1×1 image returns 1×1")
    func tileSizeOneByOne() {
        let (tw, th) = optimalTileSize(imageWidth: 1, imageHeight: 1, bytesPerSample: 1)
        #expect(tw == 1)
        #expect(th == 1)
    }

    @Test("optimalTileSize tile width is aligned to cache-line boundary in samples")
    func tileSizeAligned() {
        let bytesPerSample = 1
        let samplesPerCacheLine = AppleSiliconCacheParameters.cacheLineSize / bytesPerSample
        let (tw, _) = optimalTileSize(imageWidth: 3840, imageHeight: 2160, bytesPerSample: bytesPerSample)
        #expect(tw % samplesPerCacheLine == 0 || tw <= samplesPerCacheLine,
                "Tile width should be aligned to cache-line boundary")
    }

    @Test("optimalTileSize for 16-bit samples returns smaller tile height than 8-bit")
    func tileSizeSmallerFor16Bit() {
        let (_, th8)  = optimalTileSize(imageWidth: 3840, imageHeight: 2160, bytesPerSample: 1)
        let (_, th16) = optimalTileSize(imageWidth: 3840, imageHeight: 2160, bytesPerSample: 2)
        // 16-bit rows are twice as wide, so fewer rows fit in cache
        #expect(th16 <= th8)
    }

    // MARK: - Cache-Aligned Buffer Allocation

    @Test("allocateCacheAlignedContextArray returns correct minimum size")
    func cacheAlignedMinSize() {
        let count = 365
        let buf = allocateCacheAlignedContextArray(count: count)
        #expect(buf.count >= count)
    }

    @Test("allocateCacheAlignedContextArray size is a multiple of cache-line stride")
    func cacheAlignedMultiple() {
        let stride = AppleSiliconCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
        for count in [1, 100, 365, 384, 1000] {
            let buf = allocateCacheAlignedContextArray(count: count)
            #expect(buf.count % stride == 0,
                    "Allocated count \(buf.count) should be a multiple of \(stride) for count \(count)")
        }
    }

    @Test("allocateCacheAlignedContextArray is zero-initialised")
    func cacheAlignedZeroInit() {
        let buf = allocateCacheAlignedContextArray(count: 100)
        #expect(buf.allSatisfy { $0 == 0 })
    }

    // MARK: - Unified Memory Buffer Pool

    @Test("UnifiedMemoryBufferPool acquire returns correct buffer size")
    func poolAcquireSize() {
        let pool = UnifiedMemoryBufferPool(bufferSize: 1024, poolCapacity: 2)
        let buf = pool.acquire()
        #expect(buf.count == 1024)
    }

    @Test("UnifiedMemoryBufferPool release and re-acquire reuses buffer")
    func poolReuseBuffer() {
        let pool = UnifiedMemoryBufferPool(bufferSize: 512, poolCapacity: 2)
        let buf = pool.acquire()
        pool.release(buf)
        #expect(pool.availableCount == 1)
        let buf2 = pool.acquire()
        #expect(buf2.count == 512)
        #expect(pool.availableCount == 0)
    }

    @Test("UnifiedMemoryBufferPool respects poolCapacity limit")
    func poolCapacityLimit() {
        let pool = UnifiedMemoryBufferPool(bufferSize: 128, poolCapacity: 2)
        pool.release(Data(count: 128))
        pool.release(Data(count: 128))
        pool.release(Data(count: 128))  // Third release should be discarded
        #expect(pool.availableCount == 2)
    }

    @Test("UnifiedMemoryBufferPool prewarm fills pool to capacity")
    func poolPrewarm() {
        let capacity = 3
        let pool = UnifiedMemoryBufferPool(bufferSize: 64, poolCapacity: capacity)
        pool.prewarm()
        #expect(pool.availableCount == capacity)
    }

    @Test("UnifiedMemoryBufferPool allocates new buffer when empty")
    func poolAllocatesNewBuffer() {
        let pool = UnifiedMemoryBufferPool(bufferSize: 256, poolCapacity: 2)
        // Pool is empty; acquire should still return a valid buffer
        let buf = pool.acquire()
        #expect(buf.count == 256)
        #expect(pool.availableCount == 0)
    }

    // MARK: - Memory-Mapped I/O

    @Test("memoryMappedData reads a file correctly")
    func memoryMappedReadWrite() throws {
        // Write a temporary file and read it back via memory mapping
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jlswift_mmap_test_\(Int.random(in: 0..<Int.max)).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }
        
        let original = Data((0..<256).map { UInt8($0) })
        try writeMemoryMapped(original, to: tmp)
        
        let mapped = try memoryMappedData(at: tmp)
        #expect(mapped == original)
    }

    // MARK: - Tuning Parameters

    @Test("AppleSiliconTuningParameters values are positive")
    func tuningParamsPositive() {
        #expect(AppleSiliconTuningParameters.recommendedReset > 0)
        #expect(AppleSiliconTuningParameters.metalGpuThreshold > 0)
        #expect(AppleSiliconTuningParameters.stripHeight > 0)
        #expect(AppleSiliconTuningParameters.contextArrayCount > 0)
    }

    @Test("AppleSiliconTuningParameters contextArrayCount >= 367")
    func tuningContextArrayCount() {
        // Must cover at least 365 regular contexts + 2 run-interruption contexts
        #expect(AppleSiliconTuningParameters.contextArrayCount >= 367)
    }

    @Test("AppleSiliconTuningParameters contextArrayCount is aligned to cache-line boundary")
    func tuningContextArrayCountAligned() {
        let stride = AppleSiliconCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
        #expect(AppleSiliconTuningParameters.contextArrayCount % stride == 0)
    }

    // MARK: - Prefetch Hints

    @Test("prefetchContextArray does not crash with valid index")
    func prefetchValidIndex() {
        let arr = [Int](repeating: 42, count: 100)
        // Just verify it doesn't crash
        prefetchContextArray(arr, startIndex: 0, count: 64)
        prefetchContextArray(arr, startIndex: 50, count: 64)
    }

    @Test("prefetchContextArray does not crash with out-of-bounds start")
    func prefetchOutOfBoundsStart() {
        let arr = [Int](repeating: 0, count: 10)
        // Should be a no-op, not a crash
        prefetchContextArray(arr, startIndex: 100, count: 10)
    }

    @Test("prefetchContextArray does not crash with empty array")
    func prefetchEmptyArray() {
        prefetchContextArray([], startIndex: 0, count: 10)
    }
}

#endif // arch(arm64)
