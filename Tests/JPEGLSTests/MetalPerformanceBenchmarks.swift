/// Performance benchmarks for Metal GPU acceleration.
///
/// These benchmarks measure the performance of Metal GPU-accelerated operations
/// compared to CPU implementations, helping to identify optimal use cases and
/// validate the GPU threshold heuristic.

#if canImport(Metal)

import Testing
@testable import JPEGLS
import Foundation

@Suite("Metal GPU Performance Benchmarks")
struct MetalPerformanceBenchmarks {
    
    // MARK: - Benchmark Configuration
    
    /// Number of iterations for benchmark measurements
    private static let benchmarkIterations = 5
    
    /// Warmup iterations to let the GPU reach steady state
    private static let warmupIterations = 2
    
    // MARK: - Helper Methods
    
    /// Measure execution time of a block of code
    private func measure(iterations: Int = benchmarkIterations, _ block: () throws -> Void) rethrows -> (min: TimeInterval, max: TimeInterval, avg: TimeInterval) {
        var times: [TimeInterval] = []
        
        for _ in 0..<iterations {
            let start = Date()
            try block()
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let min = times.min() ?? 0
        let max = times.max() ?? 0
        let avg = times.reduce(0, +) / Double(times.count)
        
        return (min, max, avg)
    }
    
    /// Generate random test data
    private func generateTestData(count: Int) -> (a: [Int32], b: [Int32], c: [Int32]) {
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            a[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
            c[i] = Int32.random(in: 0...255)
        }
        
        return (a, b, c)
    }
    
    // MARK: - Gradient Computation Benchmarks
    
    @Test("Benchmark: Metal gradient computation - 512×512 (below threshold)")
    func benchmarkGradients512x512() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 512 * 512  // 262,144 pixels (below GPU threshold)
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        
        print("""
        
        Metal Gradients 512×512 (Below GPU Threshold):
          Image:          512×512 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
          Note:           Should use CPU fallback
        """)
    }
    
    @Test("Benchmark: Metal gradient computation - 1024×1024 (at threshold)")
    func benchmarkGradients1024x1024() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 1024 * 1024  // 1,048,576 pixels (just above GPU threshold)
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        
        print("""
        
        Metal Gradients 1024×1024 (At GPU Threshold):
          Image:          1024×1024 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
          Note:           Should use GPU
        """)
    }
    
    @Test("Benchmark: Metal gradient computation - 2048×2048 (large image)")
    func benchmarkGradients2048x2048() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 2048 * 2048  // 4,194,304 pixels
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        let dataSize = Double(count * 3 * MemoryLayout<Int32>.size) / (1024 * 1024)
        
        print("""
        
        Metal Gradients 2048×2048 (Large Image):
          Image:          2048×2048 (\(count) pixels)
          Data size:      \(String(format: "%.2f", dataSize)) MB
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
          Note:           Should show GPU benefit
        """)
    }
    
    @Test("Benchmark: Metal gradient computation - 4096×4096 (very large)")
    func benchmarkGradients4096x4096() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 4096 * 4096  // 16,777,216 pixels
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        let dataSize = Double(count * 3 * MemoryLayout<Int32>.size) / (1024 * 1024)
        
        print("""
        
        Metal Gradients 4096×4096 (Very Large Image):
          Image:          4096×4096 (\(count) pixels)
          Data size:      \(String(format: "%.2f", dataSize)) MB
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
          Note:           Should show maximum GPU benefit
        """)
    }
    
    // MARK: - MED Prediction Benchmarks
    
    @Test("Benchmark: Metal MED prediction - 1024×1024")
    func benchmarkMEDPrediction1024x1024() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 1024 * 1024
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        
        print("""
        
        Metal MED Prediction 1024×1024:
          Image:          1024×1024 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
        """)
    }
    
    @Test("Benchmark: Metal MED prediction - 2048×2048")
    func benchmarkMEDPrediction2048x2048() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = generateTestData(count: count)
        
        // Warmup
        for _ in 0..<Self.warmupIterations {
            _ = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        // Measure
        let (minTime, maxTime, avgTime) = measure {
            _ = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        let throughput = Double(count) / avgTime / 1_000_000.0
        
        print("""
        
        Metal MED Prediction 2048×2048:
          Image:          2048×2048 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          Average time:   \(String(format: "%.2f", avgTime * 1000)) ms
          Min time:       \(String(format: "%.2f", minTime * 1000)) ms
          Max time:       \(String(format: "%.2f", maxTime * 1000)) ms
          Throughput:     \(String(format: "%.2f", throughput)) Mpixels/s
        """)
    }
    
    // MARK: - CPU vs GPU Comparison
    
    @Test("Benchmark: CPU vs GPU comparison - 2048×2048 gradients")
    func benchmarkCPUvsGPUGradients() throws {
        #guard(MetalAccelerator.isSupported)
        
        let metalAccelerator = try MetalAccelerator()
        let scalarAccelerator = ScalarAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = generateTestData(count: count)
        
        // Benchmark GPU
        for _ in 0..<Self.warmupIterations {
            _ = try metalAccelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        let (_, _, gpuTime) = measure {
            _ = try metalAccelerator.computeGradientsBatch(a: a, b: b, c: c)
        }
        
        // Benchmark CPU (scalar implementation)
        let (_, _, cpuTime) = measure {
            for i in 0..<count {
                _ = scalarAccelerator.computeGradients(a: Int(a[i]), b: Int(b[i]), c: Int(c[i]))
            }
        }
        
        let speedup = cpuTime / gpuTime
        let gpuThroughput = Double(count) / gpuTime / 1_000_000.0
        let cpuThroughput = Double(count) / cpuTime / 1_000_000.0
        
        print("""
        
        CPU vs GPU Comparison - 2048×2048 Gradients:
          Image:          2048×2048 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          
          GPU (Metal):
            Average time:   \(String(format: "%.2f", gpuTime * 1000)) ms
            Throughput:     \(String(format: "%.2f", gpuThroughput)) Mpixels/s
          
          CPU (Scalar):
            Average time:   \(String(format: "%.2f", cpuTime * 1000)) ms
            Throughput:     \(String(format: "%.2f", cpuThroughput)) Mpixels/s
          
          Speedup:          \(String(format: "%.2f", speedup))×
        """)
    }
    
    @Test("Benchmark: CPU vs GPU comparison - 2048×2048 MED prediction")
    func benchmarkCPUvsGPUMEDPrediction() throws {
        #guard(MetalAccelerator.isSupported)
        
        let metalAccelerator = try MetalAccelerator()
        let scalarAccelerator = ScalarAccelerator()
        let count = 2048 * 2048
        let (a, b, c) = generateTestData(count: count)
        
        // Benchmark GPU
        for _ in 0..<Self.warmupIterations {
            _ = try metalAccelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        let (_, _, gpuTime) = measure {
            _ = try metalAccelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        }
        
        // Benchmark CPU (scalar implementation)
        let (_, _, cpuTime) = measure {
            for i in 0..<count {
                _ = scalarAccelerator.medPredictor(a: Int(a[i]), b: Int(b[i]), c: Int(c[i]))
            }
        }
        
        let speedup = cpuTime / gpuTime
        let gpuThroughput = Double(count) / gpuTime / 1_000_000.0
        let cpuThroughput = Double(count) / cpuTime / 1_000_000.0
        
        print("""
        
        CPU vs GPU Comparison - 2048×2048 MED Prediction:
          Image:          2048×2048 (\(count) pixels)
          Iterations:     \(Self.benchmarkIterations)
          
          GPU (Metal):
            Average time:   \(String(format: "%.2f", gpuTime * 1000)) ms
            Throughput:     \(String(format: "%.2f", gpuThroughput)) Mpixels/s
          
          CPU (Scalar):
            Average time:   \(String(format: "%.2f", cpuTime * 1000)) ms
            Throughput:     \(String(format: "%.2f", cpuThroughput)) Mpixels/s
          
          Speedup:          \(String(format: "%.2f", speedup))×
        """)
    }
}

#endif // canImport(Metal)
