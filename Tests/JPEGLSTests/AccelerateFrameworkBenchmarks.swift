import Testing
import Foundation
@testable import JPEGLS

#if canImport(Accelerate)

/// Benchmarks for comparing Accelerate framework implementations.
///
/// These benchmarks measure the performance of Accelerate vDSP-based
/// batch operations compared to scalar implementations and evaluate
/// the overhead of batch processing.
@Suite("Accelerate Framework Benchmarks")
struct AccelerateFrameworkBenchmarks {
    // MARK: - Batch Gradient Computation Benchmarks
    
    @Test("Benchmark: Batch gradient computation vs scalar")
    func benchmarkBatchGradients() {
        let scalarAccelerator = ScalarAccelerator()
        let accelerateAccelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let count = 1000
        let a = (0..<count).map { $0 % 256 }
        let b = (0..<count).map { ($0 + 1) % 256 }
        let c = (0..<count).map { ($0 + 2) % 256 }
        
        // Benchmark scalar implementation (per-element)
        let scalarStart = Date()
        var scalarResults: [(d1: [Int], d2: [Int], d3: [Int])] = []
        for _ in 0..<10 {
            var d1: [Int] = []
            var d2: [Int] = []
            var d3: [Int] = []
            for i in 0..<count {
                let result = scalarAccelerator.computeGradients(a: a[i], b: b[i], c: c[i])
                d1.append(result.d1)
                d2.append(result.d2)
                d3.append(result.d3)
            }
            scalarResults.append((d1, d2, d3))
        }
        let scalarTime = Date().timeIntervalSince(scalarStart)
        
        // Benchmark Accelerate batch implementation
        let accelerateStart = Date()
        var accelerateResults: [(d1: [Int], d2: [Int], d3: [Int])] = []
        for _ in 0..<10 {
            let result = accelerateAccelerator.computeGradientsBatch(a: a, b: b, c: c)
            accelerateResults.append(result)
        }
        let accelerateTime = Date().timeIntervalSince(accelerateStart)
        
        // Verify results are identical
        for i in 0..<count {
            #expect(scalarResults[0].d1[i] == accelerateResults[0].d1[i])
            #expect(scalarResults[0].d2[i] == accelerateResults[0].d2[i])
            #expect(scalarResults[0].d3[i] == accelerateResults[0].d3[i])
        }
        
        // Report performance comparison
        let speedup = scalarTime / accelerateTime
        print("Batch Gradient Computation Benchmark:")
        print("  Scalar time:      \(String(format: "%.6f", scalarTime))s")
        print("  Accelerate time:  \(String(format: "%.6f", accelerateTime))s")
        print("  Speedup:          \(String(format: "%.2f", speedup))x")
        
        // Test should pass regardless of speedup (just measuring)
        #expect(true)
    }
    
    // MARK: - Statistical Operations Benchmarks
    
    @Test("Benchmark: Mean computation")
    func benchmarkMean() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let values = (0..<10_000).map { $0 % 256 }
        
        // Benchmark Accelerate implementation
        let start = Date()
        for _ in 0..<100 {
            _ = accelerator.computeMean(values: values)
        }
        let time = Date().timeIntervalSince(start)
        
        print("Mean Computation Benchmark:")
        print("  Time for 100 iterations: \(String(format: "%.6f", time))s")
        print("  Average per call: \(String(format: "%.6f", time / 100))s")
        
        #expect(true)
    }
    
    @Test("Benchmark: Variance computation")
    func benchmarkVariance() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let values = (0..<10_000).map { $0 % 256 }
        
        // Benchmark Accelerate implementation
        let start = Date()
        for _ in 0..<100 {
            _ = accelerator.computeVariance(values: values)
        }
        let time = Date().timeIntervalSince(start)
        
        print("Variance Computation Benchmark:")
        print("  Time for 100 iterations: \(String(format: "%.6f", time))s")
        print("  Average per call: \(String(format: "%.6f", time / 100))s")
        
        #expect(true)
    }
    
    @Test("Benchmark: Histogram computation")
    func benchmarkHistogram() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let pixels = (0..<10_000).map { $0 % 256 }
        
        // Benchmark Accelerate implementation
        let start = Date()
        for _ in 0..<100 {
            _ = accelerator.computeHistogram(
                pixels: pixels,
                binCount: 256,
                minValue: 0,
                maxValue: 256
            )
        }
        let time = Date().timeIntervalSince(start)
        
        print("Histogram Computation Benchmark:")
        print("  Time for 100 iterations: \(String(format: "%.6f", time))s")
        print("  Average per call: \(String(format: "%.6f", time / 100))s")
        
        #expect(true)
    }
    
    // MARK: - Vector Operations Benchmarks
    
    @Test("Benchmark: Array addition")
    func benchmarkArrayAddition() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let count = 10_000
        let a = (0..<count).map { $0 % 256 }
        let b = (0..<count).map { ($0 + 1) % 256 }
        
        // Benchmark Accelerate implementation
        let accelerateStart = Date()
        for _ in 0..<100 {
            _ = accelerator.addArrays(a: a, b: b)
        }
        let accelerateTime = Date().timeIntervalSince(accelerateStart)
        
        // Benchmark naive Swift implementation
        let naiveStart = Date()
        for _ in 0..<100 {
            _ = zip(a, b).map { $0 + $1 }
        }
        let naiveTime = Date().timeIntervalSince(naiveStart)
        
        // Report performance comparison
        let speedup = naiveTime / accelerateTime
        print("Array Addition Benchmark:")
        print("  Naive Swift time:  \(String(format: "%.6f", naiveTime))s")
        print("  Accelerate time:   \(String(format: "%.6f", accelerateTime))s")
        print("  Speedup:           \(String(format: "%.2f", speedup))x")
        
        #expect(true)
    }
    
    @Test("Benchmark: Array subtraction")
    func benchmarkArraySubtraction() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let count = 10_000
        let a = (0..<count).map { $0 % 256 }
        let b = (0..<count).map { ($0 + 1) % 256 }
        
        // Benchmark Accelerate implementation
        let accelerateStart = Date()
        for _ in 0..<100 {
            _ = accelerator.subtractArrays(a: a, b: b)
        }
        let accelerateTime = Date().timeIntervalSince(accelerateStart)
        
        // Benchmark naive Swift implementation
        let naiveStart = Date()
        for _ in 0..<100 {
            _ = zip(a, b).map { $0 - $1 }
        }
        let naiveTime = Date().timeIntervalSince(naiveStart)
        
        // Report performance comparison
        let speedup = naiveTime / accelerateTime
        print("Array Subtraction Benchmark:")
        print("  Naive Swift time:  \(String(format: "%.6f", naiveTime))s")
        print("  Accelerate time:   \(String(format: "%.6f", accelerateTime))s")
        print("  Speedup:           \(String(format: "%.2f", speedup))x")
        
        #expect(true)
    }
    
    @Test("Benchmark: Scalar multiplication")
    func benchmarkScalarMultiplication() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Generate test data
        let count = 10_000
        let array = (0..<count).map { $0 % 256 }
        let scalar = 3
        
        // Benchmark Accelerate implementation
        let accelerateStart = Date()
        for _ in 0..<100 {
            _ = accelerator.multiplyByScalar(array: array, scalar: scalar)
        }
        let accelerateTime = Date().timeIntervalSince(accelerateStart)
        
        // Benchmark naive Swift implementation
        let naiveStart = Date()
        for _ in 0..<100 {
            _ = array.map { $0 * scalar }
        }
        let naiveTime = Date().timeIntervalSince(naiveStart)
        
        // Report performance comparison
        let speedup = naiveTime / accelerateTime
        print("Scalar Multiplication Benchmark:")
        print("  Naive Swift time:  \(String(format: "%.6f", naiveTime))s")
        print("  Accelerate time:   \(String(format: "%.6f", accelerateTime))s")
        print("  Speedup:           \(String(format: "%.2f", speedup))x")
        
        #expect(true)
    }
    
    // MARK: - Batch Size Analysis
    
    @Test("Benchmark: Batch size impact on performance")
    func benchmarkBatchSizeImpact() {
        let scalarAccelerator = ScalarAccelerator()
        let accelerateAccelerator = AccelerateFrameworkAccelerator()
        
        let batchSizes = [10, 100, 1000, 10000]
        
        print("Batch Size Impact Analysis:")
        print("  Batch Size | Scalar Time | Accelerate Time | Speedup")
        print("  -----------|-------------|-----------------|--------")
        
        for batchSize in batchSizes {
            let a = (0..<batchSize).map { $0 % 256 }
            let b = (0..<batchSize).map { ($0 + 1) % 256 }
            let c = (0..<batchSize).map { ($0 + 2) % 256 }
            
            let iterations = max(1, 1000 / batchSize)
            
            // Scalar
            let scalarStart = Date()
            for _ in 0..<iterations {
                for i in 0..<batchSize {
                    _ = scalarAccelerator.computeGradients(a: a[i], b: b[i], c: c[i])
                }
            }
            let scalarTime = Date().timeIntervalSince(scalarStart)
            
            // Accelerate
            let accelerateStart = Date()
            for _ in 0..<iterations {
                _ = accelerateAccelerator.computeGradientsBatch(a: a, b: b, c: c)
            }
            let accelerateTime = Date().timeIntervalSince(accelerateStart)
            
            let speedup = scalarTime / accelerateTime
            print("  \(String(format: "%10d", batchSize)) | \(String(format: "%11.6f", scalarTime))s | \(String(format: "%15.6f", accelerateTime))s | \(String(format: "%6.2f", speedup))x")
        }
        
        #expect(true)
    }
}

#endif
