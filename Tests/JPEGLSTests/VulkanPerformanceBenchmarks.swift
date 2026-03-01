/// Vulkan GPU compute performance benchmarks (Phase 15.3).
///
/// These benchmarks measure the performance of `VulkanAccelerator` operations
/// via the CPU-fallback path, which executes the same algorithms that the
/// Vulkan GPU path will use. The results document CPU-path performance
/// characteristics and serve as a baseline for future GPU comparison once
/// the Vulkan SDK integration is complete.
///
/// All benchmarks exercise the full configuration matrix:
/// - Multiple image sizes (small, medium, large, very large)
/// - All accelerated operations (gradients, MED prediction, quantisation,
///   colour transforms)
///
/// These tests run on all platforms (no Vulkan SDK required).

import Testing
@testable import JPEGLS
import Foundation

@Suite("Vulkan CPU-Fallback Performance Benchmarks")
struct VulkanPerformanceBenchmarks {

    // MARK: - Configuration

    private static let warmupIterations = 2
    private static let benchmarkIterations = 5

    // MARK: - Helpers

    private func measure(
        iterations: Int = VulkanPerformanceBenchmarks.benchmarkIterations,
        _ block: () -> Void
    ) -> (min: TimeInterval, max: TimeInterval, avg: TimeInterval) {
        var times: [TimeInterval] = []
        for _ in 0..<iterations {
            let start = Date()
            block()
            times.append(Date().timeIntervalSince(start))
        }
        let mn = times.min() ?? 0
        let mx = times.max() ?? 0
        let avg = times.reduce(0, +) / Double(times.count)
        return (mn, mx, avg)
    }

    private func makePixelData(count: Int) -> (a: [Int32], b: [Int32], c: [Int32]) {
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i % 256)
            b[i] = Int32((i + 85)  % 256)
            c[i] = Int32((i + 170) % 256)
        }
        return (a, b, c)
    }

    // MARK: - Gradient Computation Benchmarks

    @Test("Benchmark: Vulkan gradients — 64×64 (small image)")
    func benchmarkGradients64x64() {
        let accelerator = VulkanAccelerator()
        let count = 64 * 64
        let (a, b, c) = makePixelData(count: count)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan Gradients 64×64:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
        // Verify correctness while benchmarking
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.count == count)
        #expect(d2.count == count)
        #expect(d3.count == count)
    }

    @Test("Benchmark: Vulkan gradients — 512×512 (medium image)")
    func benchmarkGradients512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        let (a, b, c) = makePixelData(count: count)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan Gradients 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    @Test("Benchmark: Vulkan gradients — 2048×2048 (large image)")
    func benchmarkGradients2048x2048() {
        let accelerator = VulkanAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = makePixelData(count: count)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        let dataSize   = Double(count * 3 * MemoryLayout<Int32>.size) / (1024 * 1024)
        print("""
        
        Vulkan Gradients 2048×2048:
          Pixels:       \(count)
          Data:         \(String(format: "%.1f", dataSize)) MB
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    // MARK: - MED Prediction Benchmarks

    @Test("Benchmark: Vulkan MED prediction — 512×512")
    func benchmarkMEDPrediction512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        let (a, b, c) = makePixelData(count: count)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan MED Prediction 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    @Test("Benchmark: Vulkan MED prediction — 2048×2048")
    func benchmarkMEDPrediction2048x2048() {
        let accelerator = VulkanAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = makePixelData(count: count)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan MED Prediction 2048×2048:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    // MARK: - Gradient Quantisation Benchmarks

    @Test("Benchmark: Vulkan gradient quantisation — 512×512")
    func benchmarkQuantise512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        var d1 = [Int32](repeating: 0, count: count)
        var d2 = [Int32](repeating: 0, count: count)
        var d3 = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            d1[i] = Int32((i % 50) - 25)
            d2[i] = Int32((i % 30) - 15)
            d3[i] = Int32((i % 40) - 20)
        }
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.quantizeGradientsBatch(
                d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.quantizeGradientsBatch(
                d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan Gradient Quantisation 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    // MARK: - Colour Transform Benchmarks

    @Test("Benchmark: Vulkan HP1 colour transform — 512×512")
    func benchmarkColourTransformHP1_512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 85)  % 256)
            b[i] = Int32((i + 170) % 256)
        }
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.applyColourTransformForwardBatch(
                transform: .hp1, r: r, g: g, b: b)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.applyColourTransformForwardBatch(
                transform: .hp1, r: r, g: g, b: b)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan HP1 Colour Transform (forward) 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    @Test("Benchmark: Vulkan HP3 colour transform — 2048×2048")
    func benchmarkColourTransformHP3_2048x2048() {
        let accelerator = VulkanAccelerator()
        let count = 2048 * 2048
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 85)  % 256)
            b[i] = Int32((i + 170) % 256)
        }
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = accelerator.applyColourTransformForwardBatch(
                transform: .hp3, r: r, g: g, b: b)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = accelerator.applyColourTransformForwardBatch(
                transform: .hp3, r: r, g: g, b: b)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        let dataSize   = Double(count * 3 * MemoryLayout<Int32>.size) / (1024 * 1024)
        print("""
        
        Vulkan HP3 Colour Transform (forward) 2048×2048:
          Pixels:       \(count)
          Data:         \(String(format: "%.1f", dataSize)) MB
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }

    // MARK: - Memory Management Benchmarks

    @Test("Benchmark: VulkanMemoryPool allocation and reset")
    func benchmarkMemoryPoolAllocationReset() {
        let (mnTime, mxTime, avgTime) = measure {
            let pool = VulkanMemoryPool(maxPoolSize: 64 * 1024 * 1024)
            // Simulate allocating buffers for a 512×512 3-channel operation
            let pixelCount = 512 * 512
            let byteCount  = pixelCount * MemoryLayout<Int32>.stride
            _ = try? pool.allocate(size: byteCount, usage: .storageBuffer)  // a
            _ = try? pool.allocate(size: byteCount, usage: .storageBuffer)  // b
            _ = try? pool.allocate(size: byteCount, usage: .storageBuffer)  // c
            _ = try? pool.allocate(size: byteCount, usage: .storageBuffer)  // output
            pool.reset()
        }
        print("""
        
        VulkanMemoryPool alloc+reset (4 × 512×512 buffers):
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
        """)
    }

    @Test("Benchmark: VulkanBuffer write and read round-trip")
    func benchmarkBufferWriteReadRoundTrip() {
        let count   = 512 * 512
        let pixels  = (0..<count).map { Int32($0 % 256) }
        let (mnTime, mxTime, avgTime) = measure {
            let buf = try! VulkanBuffer(
                size: count * MemoryLayout<Int32>.stride, usage: .storageBuffer)
            buf.write(pixels)
            _ = buf.read(count: count, type: Int32.self)
        }
        print("""
        
        VulkanBuffer write+read (512×512 Int32):
          Elements:     \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
        """)
        // Correctness check
        let buf = try! VulkanBuffer(
            size: count * MemoryLayout<Int32>.stride, usage: .transferSrc)
        buf.write(pixels)
        let result = buf.read(count: count, type: Int32.self)
        #expect(result == pixels)
    }

    // MARK: - Encoding/Decoding Pipeline Benchmarks

    @Test("Benchmark: Vulkan encoding pipeline — 512×512")
    func benchmarkEncodingPipeline512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        let (a, b, c) = makePixelData(count: count)
        let x = (0..<count).map { Int32(($0 + 50) % 256) }
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = try? accelerator.computeEncodingPipelineBatch(
                a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = try? accelerator.computeEncodingPipelineBatch(
                a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan Encoding Pipeline 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
        // Correctness check: prediction + error == x for lossless
        let (pred, err, _, _, _) = try! accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        for i in 0..<count {
            #expect(pred[i] + err[i] == x[i])
        }
    }

    @Test("Benchmark: Vulkan decoding pipeline — 512×512")
    func benchmarkDecodingPipeline512x512() {
        let accelerator = VulkanAccelerator()
        let count = 512 * 512
        let (a, b, c) = makePixelData(count: count)
        let x = (0..<count).map { Int32(($0 + 50) % 256) }
        let (_, errval, _, _, _) = try! accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = try? accelerator.computeDecodingPipelineBatch(a: a, b: b, c: c, errval: errval)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = try? accelerator.computeDecodingPipelineBatch(a: a, b: b, c: c, errval: errval)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        print("""
        
        Vulkan Decoding Pipeline 512×512:
          Pixels:       \(count)
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
        // Correctness check: lossless encode → decode reconstructs x
        let reconstructed = try! accelerator.computeDecodingPipelineBatch(
            a: a, b: b, c: c, errval: errval)
        #expect(reconstructed == x)
    }

    @Test("Benchmark: Vulkan encoding pipeline — 2048×2048")
    func benchmarkEncodingPipeline2048x2048() {
        let accelerator = VulkanAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = makePixelData(count: count)
        let x = (0..<count).map { Int32(($0 + 50) % 256) }
        for _ in 0..<VulkanPerformanceBenchmarks.warmupIterations {
            _ = try? accelerator.computeEncodingPipelineBatch(
                a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        }
        let (mnTime, mxTime, avgTime) = measure {
            _ = try? accelerator.computeEncodingPipelineBatch(
                a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        }
        let throughput = Double(count) / avgTime / 1_000_000.0
        let dataSize   = Double(count * 4 * MemoryLayout<Int32>.size) / (1024 * 1024)
        print("""
        
        Vulkan Encoding Pipeline 2048×2048:
          Pixels:       \(count)
          Data:         \(String(format: "%.1f", dataSize)) MB
          Avg time:     \(String(format: "%.3f", avgTime * 1000)) ms
          Min/Max:      \(String(format: "%.3f", mnTime * 1000)) / \(String(format: "%.3f", mxTime * 1000)) ms
          Throughput:   \(String(format: "%.2f", throughput)) Mpix/s  (CPU fallback)
        """)
    }
}
