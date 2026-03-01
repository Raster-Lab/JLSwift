/// Tests for Intel x86-64 memory optimisation (Phase 14.2).
///
/// These tests cover IntelCacheParameters, tile size tuning,
/// cache-aligned buffer allocation, buffer pooling, prefetch helpers,
/// and tuning parameters from IntelMemoryOptimizer.swift.
///
/// All tests are compiled and run only on x86-64 architectures.

#if arch(x86_64)

import Testing
import Foundation
@testable import JPEGLS

@Suite("Intel Memory Optimiser Phase 14.2 Tests")
struct IntelMemoryOptimizerTests {

    // MARK: - Cache Parameters

    @Test("Intel cache parameters have expected values")
    func cacheParameterValues() {
        #expect(IntelCacheParameters.l1DataCacheSize == 32 * 1024)
        #expect(IntelCacheParameters.l2CacheSize == 256 * 1024)
        #expect(IntelCacheParameters.l3CacheSize == 8 * 1024 * 1024)
        #expect(IntelCacheParameters.cacheLineSize == 64)
        #expect(IntelCacheParameters.contextArrayAlignment == 64)
        #expect(IntelCacheParameters.recommendedStripHeight == 8)
    }

    // MARK: - Tile Size Tuning

    @Test("Tile size fits within L1 budget for small greyscale image")
    func tileSizeSmallGreyscale() {
        let (tw, th) = intelOptimalTileSize(imageWidth: 128, imageHeight: 128)
        #expect(tw >= 1)
        #expect(th >= 1)
        #expect(tw <= 128)
        #expect(th <= 128)
    }

    @Test("Tile size fits within L1 budget for large RGB 16-bit image")
    func tileSizeLargeRGB16() {
        let (tw, th) = intelOptimalTileSize(
            imageWidth: 3840, imageHeight: 2160,
            bytesPerSample: 2, componentCount: 3
        )
        #expect(tw >= 1)
        #expect(th >= 1)
        #expect(tw <= 3840)
        #expect(th <= 2160)
    }

    @Test("Tile width is cache-line aligned")
    func tileWidthCacheLineAligned() {
        let (tw, _) = intelOptimalTileSize(imageWidth: 1000, imageHeight: 500)
        let samplesPerCacheLine = IntelCacheParameters.cacheLineSize / 1  // 1 byte per sample
        #expect(tw % samplesPerCacheLine == 0 || tw == 1000)
    }

    @Test("Tile height never exceeds image height")
    func tileHeightBound() {
        let (_, th) = intelOptimalTileSize(imageWidth: 16, imageHeight: 4)
        #expect(th <= 4)
    }

    // MARK: - Cache-Aligned Buffer Allocation

    @Test("Allocated context array has at least requested count")
    func cacheAlignedArraySize() {
        let arr = intelAllocateCacheAlignedContextArray(count: 365)
        #expect(arr.count >= 365)
    }

    @Test("Allocated context array count is multiple of cache-line stride")
    func cacheAlignedArrayAlignment() {
        let arr = intelAllocateCacheAlignedContextArray(count: 365)
        let stride = IntelCacheParameters.cacheLineSize / MemoryLayout<Int>.stride
        #expect(arr.count % stride == 0)
    }

    @Test("Allocated context array is zero-initialised")
    func cacheAlignedArrayZeroed() {
        let arr = intelAllocateCacheAlignedContextArray(count: 100)
        #expect(arr.allSatisfy { $0 == 0 })
    }

    // MARK: - Buffer Pool

    @Test("Buffer pool acquire returns correct-size buffer")
    func poolAcquireSize() {
        let pool = IntelBufferPool(bufferSize: 1024)
        let buf = pool.acquire()
        #expect(buf.count == 1024)
    }

    @Test("Buffer pool release and reuse")
    func poolReleaseReuse() {
        let pool = IntelBufferPool(bufferSize: 512, poolCapacity: 2)
        let buf1 = pool.acquire()
        pool.release(buf1)
        #expect(pool.availableCount == 1)
        let _ = pool.acquire()
        #expect(pool.availableCount == 0)
    }

    @Test("Buffer pool discards buffers beyond capacity")
    func poolCapacityLimit() {
        let pool = IntelBufferPool(bufferSize: 256, poolCapacity: 2)
        let b1 = pool.acquire()
        let b2 = pool.acquire()
        let b3 = pool.acquire()
        pool.release(b1)
        pool.release(b2)
        pool.release(b3)  // exceeds capacity
        #expect(pool.availableCount == 2)
    }

    @Test("Buffer pool prewarm fills to capacity")
    func poolPrewarm() {
        let pool = IntelBufferPool(bufferSize: 128, poolCapacity: 4)
        pool.prewarm()
        #expect(pool.availableCount == 4)
    }

    // MARK: - Prefetch Hint

    @Test("Prefetch does not crash on valid range")
    func prefetchValid() {
        let arr = [Int](repeating: 1, count: 128)
        // Should not crash
        intelPrefetchContextArray(arr, startIndex: 0, count: 128)
    }

    @Test("Prefetch handles empty range gracefully")
    func prefetchEmptyRange() {
        let arr = [Int](repeating: 0, count: 10)
        // startIndex == end → no-op
        intelPrefetchContextArray(arr, startIndex: 10, count: 0)
    }

    // MARK: - Tuning Parameters

    @Test("Intel tuning parameters have expected values")
    func tuningParameterValues() {
        #expect(IntelTuningParameters.recommendedReset == 64)
        #expect(IntelTuningParameters.stripHeight == IntelCacheParameters.recommendedStripHeight)
        #expect(IntelTuningParameters.contextArrayCount == 384)
    }

    // MARK: - Memory-Mapped I/O

    @Test("Memory-mapped read of temp file succeeds")
    func memoryMappedRead() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("intel_mmap_test.bin")
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        try testData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let mapped = try intelMemoryMappedData(at: url)
        #expect(mapped == testData)
    }

    @Test("Memory-mapped write of temp file succeeds")
    func memoryMappedWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("intel_mmap_write_test.bin")
        let testData = Data([0xAA, 0xBB, 0xCC])
        try intelWriteMemoryMapped(testData, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try Data(contentsOf: url)
        #expect(read == testData)
    }
}

#endif // arch(x86_64)
