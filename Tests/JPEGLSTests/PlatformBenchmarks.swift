import Testing
import Foundation
@testable import JPEGLS

/// Benchmarks for comparing scalar vs SIMD platform implementations.
///
/// These benchmarks measure the performance improvement of SIMD-optimized
/// implementations compared to the scalar reference implementation.
@Suite("Platform Benchmarks")
struct PlatformBenchmarks {
    /// Sample size for benchmark iterations
    private static let benchmarkIterations = 10_000
    
    // MARK: - Gradient Computation Benchmarks
    
    @Test("Benchmark: Gradient computation performance")
    func benchmarkGradientComputation() {
        let scalar = ScalarAccelerator()
        let simd = selectPlatformAccelerator()
        
        // Generate test data
        let testCases = (0..<Self.benchmarkIterations).map { i in
            (a: i % 256, b: (i + 1) % 256, c: (i + 2) % 256)
        }
        
        // Benchmark scalar implementation
        let scalarStart = Date()
        var scalarResults: [(Int, Int, Int)] = []
        for (a, b, c) in testCases {
            scalarResults.append(scalar.computeGradients(a: a, b: b, c: c))
        }
        let scalarTime = Date().timeIntervalSince(scalarStart)
        
        // Benchmark SIMD implementation
        let simdStart = Date()
        var simdResults: [(Int, Int, Int)] = []
        for (a, b, c) in testCases {
            simdResults.append(simd.computeGradients(a: a, b: b, c: c))
        }
        let simdTime = Date().timeIntervalSince(simdStart)
        
        // Verify results are identical
        for i in 0..<testCases.count {
            #expect(scalarResults[i].0 == simdResults[i].0)
            #expect(scalarResults[i].1 == simdResults[i].1)
            #expect(scalarResults[i].2 == simdResults[i].2)
        }
        
        // Report performance comparison
        let speedup = scalarTime / simdTime
        print("Gradient Computation Benchmark:")
        print("  Scalar time: \(String(format: "%.6f", scalarTime))s")
        print("  SIMD time:   \(String(format: "%.6f", simdTime))s")
        print("  Speedup:     \(String(format: "%.2f", speedup))x")
        
        // Test should pass regardless of speedup (just measuring)
        #expect(true)
    }
    
    // MARK: - MED Predictor Benchmarks
    
    @Test("Benchmark: MED predictor performance")
    func benchmarkMEDPredictor() {
        let scalar = ScalarAccelerator()
        let simd = selectPlatformAccelerator()
        
        // Generate test data covering all three MED cases
        let testCases = (0..<Self.benchmarkIterations).map { i in
            (a: i % 256, b: (i + 50) % 256, c: (i + 100) % 256)
        }
        
        // Benchmark scalar implementation
        let scalarStart = Date()
        var scalarResults: [Int] = []
        for (a, b, c) in testCases {
            scalarResults.append(scalar.medPredictor(a: a, b: b, c: c))
        }
        let scalarTime = Date().timeIntervalSince(scalarStart)
        
        // Benchmark SIMD implementation
        let simdStart = Date()
        var simdResults: [Int] = []
        for (a, b, c) in testCases {
            simdResults.append(simd.medPredictor(a: a, b: b, c: c))
        }
        let simdTime = Date().timeIntervalSince(simdStart)
        
        // Verify results are identical
        for i in 0..<testCases.count {
            #expect(scalarResults[i] == simdResults[i])
        }
        
        // Report performance comparison
        let speedup = scalarTime / simdTime
        print("MED Predictor Benchmark:")
        print("  Scalar time: \(String(format: "%.6f", scalarTime))s")
        print("  SIMD time:   \(String(format: "%.6f", simdTime))s")
        print("  Speedup:     \(String(format: "%.2f", speedup))x")
        
        // Test should pass regardless of speedup (just measuring)
        #expect(true)
    }
    
    // MARK: - Gradient Quantization Benchmarks
    
    @Test("Benchmark: Gradient quantization performance")
    func benchmarkGradientQuantization() {
        let scalar = ScalarAccelerator()
        let simd = selectPlatformAccelerator()
        
        // Generate test data with various gradient magnitudes
        let testCases = (0..<Self.benchmarkIterations).map { i in
            (d1: (i % 100) - 50, d2: ((i + 20) % 100) - 50, d3: ((i + 40) % 100) - 50)
        }
        let t1 = 3, t2 = 7, t3 = 21
        
        // Benchmark scalar implementation
        let scalarStart = Date()
        var scalarResults: [(Int, Int, Int)] = []
        for (d1, d2, d3) in testCases {
            scalarResults.append(scalar.quantizeGradients(d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3))
        }
        let scalarTime = Date().timeIntervalSince(scalarStart)
        
        // Benchmark SIMD implementation
        let simdStart = Date()
        var simdResults: [(Int, Int, Int)] = []
        for (d1, d2, d3) in testCases {
            simdResults.append(simd.quantizeGradients(d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3))
        }
        let simdTime = Date().timeIntervalSince(simdStart)
        
        // Verify results are identical
        for i in 0..<testCases.count {
            #expect(scalarResults[i].0 == simdResults[i].0)
            #expect(scalarResults[i].1 == simdResults[i].1)
            #expect(scalarResults[i].2 == simdResults[i].2)
        }
        
        // Report performance comparison
        let speedup = scalarTime / simdTime
        print("Gradient Quantization Benchmark:")
        print("  Scalar time: \(String(format: "%.6f", scalarTime))s")
        print("  SIMD time:   \(String(format: "%.6f", simdTime))s")
        print("  Speedup:     \(String(format: "%.2f", speedup))x")
        
        // Test should pass regardless of speedup (just measuring)
        #expect(true)
    }
    
    // MARK: - Combined Operations Benchmark
    
    @Test("Benchmark: Combined gradient computation and quantization")
    func benchmarkCombinedOperations() {
        let scalar = ScalarAccelerator()
        let simd = selectPlatformAccelerator()
        
        // Generate test data
        let testCases = (0..<Self.benchmarkIterations).map { i in
            (a: i % 256, b: (i + 1) % 256, c: (i + 2) % 256)
        }
        let t1 = 3, t2 = 7, t3 = 21
        
        // Benchmark scalar implementation
        let scalarStart = Date()
        var scalarResults: [(Int, Int, Int)] = []
        for (a, b, c) in testCases {
            let gradients = scalar.computeGradients(a: a, b: b, c: c)
            let quantized = scalar.quantizeGradients(
                d1: gradients.d1, d2: gradients.d2, d3: gradients.d3,
                t1: t1, t2: t2, t3: t3
            )
            scalarResults.append(quantized)
        }
        let scalarTime = Date().timeIntervalSince(scalarStart)
        
        // Benchmark SIMD implementation
        let simdStart = Date()
        var simdResults: [(Int, Int, Int)] = []
        for (a, b, c) in testCases {
            let gradients = simd.computeGradients(a: a, b: b, c: c)
            let quantized = simd.quantizeGradients(
                d1: gradients.d1, d2: gradients.d2, d3: gradients.d3,
                t1: t1, t2: t2, t3: t3
            )
            simdResults.append(quantized)
        }
        let simdTime = Date().timeIntervalSince(simdStart)
        
        // Verify results are identical
        for i in 0..<testCases.count {
            #expect(scalarResults[i].0 == simdResults[i].0)
            #expect(scalarResults[i].1 == simdResults[i].1)
            #expect(scalarResults[i].2 == simdResults[i].2)
        }
        
        // Report performance comparison
        let speedup = scalarTime / simdTime
        print("Combined Operations Benchmark:")
        print("  Scalar time: \(String(format: "%.6f", scalarTime))s")
        print("  SIMD time:   \(String(format: "%.6f", simdTime))s")
        print("  Speedup:     \(String(format: "%.2f", speedup))x")
        
        // Test should pass regardless of speedup (just measuring)
        #expect(true)
    }
    
    // MARK: - Architecture Detection
    
    @Test("Verify correct platform accelerator selection")
    func verifyPlatformSelection() {
        let accelerator = selectPlatformAccelerator()
        
        #if arch(arm64)
        // On ARM64, should get ARM64Accelerator
        #expect(type(of: accelerator) is ARM64Accelerator.Type)
        print("Running on ARM64 with NEON acceleration")
        #elseif arch(x86_64)
        // On x86_64, should get X86_64Accelerator
        #expect(type(of: accelerator) is X86_64Accelerator.Type)
        print("Running on x86_64 with SSE/AVX acceleration")
        #else
        // On other architectures, should get ScalarAccelerator
        #expect(type(of: accelerator) is ScalarAccelerator.Type)
        print("Running on unsupported architecture with scalar fallback")
        #endif
    }
}
