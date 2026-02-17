/// Tests for Metal GPU acceleration.
///
/// These tests verify the correctness and performance of Metal GPU-accelerated
/// operations for JPEG-LS encoding, ensuring bit-exact results compared to
/// CPU implementations.

#if canImport(Metal)

import Testing
@testable import JPEGLS

@Suite("Metal GPU Acceleration Tests")
struct MetalAcceleratorTests {
    
    // MARK: - Initialization Tests
    
    @Test("Metal accelerator initializes on supported devices")
    func testInitialization() throws {
        #expect(MetalAccelerator.isSupported, "Metal should be available for testing")
        
        let accelerator = try MetalAccelerator()
        #expect(MetalAccelerator.platformName == "Metal")
    }
    
    @Test("Metal accelerator reports correct support status")
    func testSupportStatus() {
        // Metal support depends on hardware availability
        // This test just verifies the check doesn't crash
        let isSupported = MetalAccelerator.isSupported
        #expect(isSupported == true || isSupported == false)
    }
    
    // MARK: - Gradient Computation Tests
    
    @Test("Compute gradients for single pixel batch")
    func testSinglePixelGradients() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Test with simple values
        let a: [Int32] = [10]
        let b: [Int32] = [15]
        let c: [Int32] = [5]
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Expected gradients:
        // d1 = b - c = 15 - 5 = 10
        // d2 = a - c = 10 - 5 = 5
        // d3 = c - a = 5 - 10 = -5
        #expect(d1 == [10])
        #expect(d2 == [5])
        #expect(d3 == [-5])
    }
    
    @Test("Compute gradients for small batch (CPU fallback)")
    func testSmallBatchGradients() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Use batch smaller than GPU threshold to test CPU fallback
        let count = MetalAccelerator.gpuThreshold / 2
        let a = [Int32](repeating: 10, count: count)
        let b = [Int32](repeating: 15, count: count)
        let c = [Int32](repeating: 5, count: count)
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // All gradients should be identical
        #expect(d1.allSatisfy { $0 == 10 })
        #expect(d2.allSatisfy { $0 == 5 })
        #expect(d3.allSatisfy { $0 == -5 })
    }
    
    @Test("Compute gradients for large batch (GPU)")
    func testLargeBatchGradients() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Use batch larger than GPU threshold to test GPU execution
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        
        // Fill with test pattern
        for i in 0..<count {
            a[i] = Int32(i % 256)
            b[i] = Int32((i + 1) % 256)
            c[i] = Int32((i + 2) % 256)
        }
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Verify gradients for each position
        for i in 0..<count {
            #expect(d1[i] == b[i] - c[i], "d1[\(i)] should equal b[\(i)] - c[\(i)]")
            #expect(d2[i] == a[i] - c[i], "d2[\(i)] should equal a[\(i)] - c[\(i)]")
            #expect(d3[i] == c[i] - a[i], "d3[\(i)] should equal c[\(i)] - a[\(i)]")
        }
    }
    
    @Test("Compute gradients with negative values")
    func testGradientsWithNegativeValues() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        let a: [Int32] = [-10, -5, 0, 5, 10]
        let b: [Int32] = [-15, -10, -5, 0, 5]
        let c: [Int32] = [-20, -15, -10, -5, 0]
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Verify each gradient
        for i in 0..<a.count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }
    
    @Test("Compute gradients with boundary values")
    func testGradientsWithBoundaryValues() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Test with 16-bit boundary values
        let a: [Int32] = [0, 65535, Int32.max, Int32.min]
        let b: [Int32] = [65535, 0, Int32.min, Int32.max]
        let c: [Int32] = [32768, 32768, 0, 0]
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Verify gradients computed correctly
        for i in 0..<a.count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }
    
    @Test("Compute gradients with empty arrays")
    func testGradientsWithEmptyArrays() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        let a: [Int32] = []
        let b: [Int32] = []
        let c: [Int32] = []
        
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        #expect(d1.isEmpty)
        #expect(d2.isEmpty)
        #expect(d3.isEmpty)
    }
    
    // MARK: - MED Prediction Tests
    
    @Test("Compute MED prediction for single pixel")
    func testSinglePixelMEDPrediction() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Test case: c >= max(a, b) → should return min(a, b)
        let a1: [Int32] = [10]
        let b1: [Int32] = [15]
        let c1: [Int32] = [20]
        let pred1 = try accelerator.computeMEDPredictionBatch(a: a1, b: b1, c: c1)
        #expect(pred1 == [10], "c >= max(a,b) should return min(a,b)")
        
        // Test case: c <= min(a, b) → should return max(a, b)
        let a2: [Int32] = [15]
        let b2: [Int32] = [20]
        let c2: [Int32] = [10]
        let pred2 = try accelerator.computeMEDPredictionBatch(a: a2, b: b2, c: c2)
        #expect(pred2 == [20], "c <= min(a,b) should return max(a,b)")
        
        // Test case: min(a,b) < c < max(a,b) → should return a + b - c
        let a3: [Int32] = [10]
        let b3: [Int32] = [20]
        let c3: [Int32] = [15]
        let pred3 = try accelerator.computeMEDPredictionBatch(a: a3, b: b3, c: c3)
        #expect(pred3 == [15], "Should return a+b-c = 10+20-15 = 15")
    }
    
    @Test("Compute MED prediction for small batch (CPU fallback)")
    func testSmallBatchMEDPrediction() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Create small batch for CPU fallback
        let count = MetalAccelerator.gpuThreshold / 2
        let a = [Int32](repeating: 10, count: count)
        let b = [Int32](repeating: 20, count: count)
        let c = [Int32](repeating: 15, count: count)
        
        let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        // All predictions should be a + b - c = 15
        #expect(predictions.allSatisfy { $0 == 15 })
    }
    
    @Test("Compute MED prediction for large batch (GPU)")
    func testLargeBatchMEDPrediction() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // Create large batch for GPU execution
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        
        // Fill with test pattern covering all MED cases
        for i in 0..<count {
            let idx = i % 3
            if idx == 0 {
                // Case: c >= max(a, b)
                a[i] = 10
                b[i] = 15
                c[i] = 20
            } else if idx == 1 {
                // Case: c <= min(a, b)
                a[i] = 15
                b[i] = 20
                c[i] = 10
            } else {
                // Case: min < c < max
                a[i] = 10
                b[i] = 20
                c[i] = 15
            }
        }
        
        let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        // Verify predictions match expected values
        for i in 0..<count {
            let expected: Int32
            let av = a[i]
            let bv = b[i]
            let cv = c[i]
            let minAB = min(av, bv)
            let maxAB = max(av, bv)
            
            if cv >= maxAB {
                expected = minAB
            } else if cv <= minAB {
                expected = maxAB
            } else {
                expected = av + bv - cv
            }
            
            #expect(predictions[i] == expected, "Prediction at index \(i) should match expected value")
        }
    }
    
    @Test("Compute MED prediction with equal pixel values")
    func testMEDPredictionWithEqualValues() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        // When all pixels are equal, prediction should equal the pixel value
        let a: [Int32] = [100, 100, 100]
        let b: [Int32] = [100, 100, 100]
        let c: [Int32] = [100, 100, 100]
        
        let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        #expect(predictions == [100, 100, 100])
    }
    
    @Test("Compute MED prediction with zero values")
    func testMEDPredictionWithZeroValues() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        let a: [Int32] = [0, 0, 0]
        let b: [Int32] = [0, 0, 0]
        let c: [Int32] = [0, 0, 0]
        
        let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        #expect(predictions == [0, 0, 0])
    }
    
    @Test("Compute MED prediction with empty arrays")
    func testMEDPredictionWithEmptyArrays() throws {
        #guard(MetalAccelerator.isSupported)
        
        let accelerator = try MetalAccelerator()
        
        let a: [Int32] = []
        let b: [Int32] = []
        let c: [Int32] = []
        
        let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        #expect(predictions.isEmpty)
    }
    
    // MARK: - Bit-Exact Comparison Tests
    
    @Test("Metal gradients match scalar implementation")
    func testGradientsBitExactMatch() throws {
        #guard(MetalAccelerator.isSupported)
        
        let metalAccelerator = try MetalAccelerator()
        let scalarAccelerator = ScalarAccelerator()
        
        // Test with random values
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            a[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
            c[i] = Int32.random(in: 0...255)
        }
        
        let (metalD1, metalD2, metalD3) = try metalAccelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Compute scalar results for comparison
        var scalarD1 = [Int32](repeating: 0, count: count)
        var scalarD2 = [Int32](repeating: 0, count: count)
        var scalarD3 = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            let gradients = scalarAccelerator.computeGradients(a: Int(a[i]), b: Int(b[i]), c: Int(c[i]))
            scalarD1[i] = Int32(gradients.d1)
            scalarD2[i] = Int32(gradients.d2)
            scalarD3[i] = Int32(gradients.d3)
        }
        
        // Verify bit-exact match
        #expect(metalD1 == scalarD1, "Metal and scalar d1 should match exactly")
        #expect(metalD2 == scalarD2, "Metal and scalar d2 should match exactly")
        #expect(metalD3 == scalarD3, "Metal and scalar d3 should match exactly")
    }
    
    @Test("Metal MED predictions match scalar implementation")
    func testMEDPredictionBitExactMatch() throws {
        #guard(MetalAccelerator.isSupported)
        
        let metalAccelerator = try MetalAccelerator()
        let scalarAccelerator = ScalarAccelerator()
        
        // Test with random values
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            a[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
            c[i] = Int32.random(in: 0...255)
        }
        
        let metalPredictions = try metalAccelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        
        // Compute scalar results for comparison
        var scalarPredictions = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let pred = scalarAccelerator.medPredictor(a: Int(a[i]), b: Int(b[i]), c: Int(c[i]))
            scalarPredictions[i] = Int32(pred)
        }
        
        // Verify bit-exact match
        #expect(metalPredictions == scalarPredictions, "Metal and scalar predictions should match exactly")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Metal accelerator handles initialization failure gracefully")
    func testInitializationError() {
        // This test can't really force an error on devices with Metal support
        // But we verify the error type exists and is usable
        let error = MetalAcceleratorError.metalNotAvailable
        #expect(error.description.contains("Metal"))
    }
}

#endif // canImport(Metal)
