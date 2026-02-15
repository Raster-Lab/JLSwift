import Testing
import Foundation
@testable import JPEGLS

#if canImport(Accelerate)

@Suite("Accelerate Framework Accelerator Tests")
struct AccelerateFrameworkAcceleratorTests {
    // MARK: - Platform Info Tests
    
    @Test("AccelerateFrameworkAccelerator platformName is correct")
    func acceleratePlatformName() {
        #expect(AccelerateFrameworkAccelerator.platformName == "Accelerate")
    }
    
    @Test("AccelerateFrameworkAccelerator is supported when Accelerate is available")
    func accelerateIsSupported() {
        #expect(AccelerateFrameworkAccelerator.isSupported == true)
    }
    
    @Test("AccelerateFrameworkAccelerator initialization")
    func accelerateInitialization() {
        let accelerator = AccelerateFrameworkAccelerator()
        // If it initializes without crashing, the test passes
        #expect(AccelerateFrameworkAccelerator.isSupported)
    }
    
    // MARK: - Batch Gradient Computation Tests
    
    @Test("Batch gradient computation with simple values")
    func batchGradientsSimple() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 20, 30]
        let b = [20, 30, 40]
        let c = [15, 25, 35]
        
        let result = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // D1 = b - c
        #expect(result.d1 == [5, 5, 5])
        
        // D2 = a - c
        #expect(result.d2 == [-5, -5, -5])
        
        // D3 = c - a
        #expect(result.d3 == [5, 5, 5])
    }
    
    @Test("Batch gradient computation with varying values")
    func batchGradientsVarying() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 50, 100]
        let b = [20, 40, 90]
        let c = [15, 45, 95]
        
        let result = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // D1 = b - c: [20-15, 40-45, 90-95] = [5, -5, -5]
        #expect(result.d1 == [5, -5, -5])
        
        // D2 = a - c: [10-15, 50-45, 100-95] = [-5, 5, 5]
        #expect(result.d2 == [-5, 5, 5])
        
        // D3 = c - a: [15-10, 45-50, 95-100] = [5, -5, -5]
        #expect(result.d3 == [5, -5, -5])
    }
    
    @Test("Batch gradient computation with zero gradients")
    func batchGradientsZero() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 10, 10]
        let b = [10, 10, 10]
        let c = [10, 10, 10]
        
        let result = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        #expect(result.d1 == [0, 0, 0])
        #expect(result.d2 == [0, 0, 0])
        #expect(result.d3 == [0, 0, 0])
    }
    
    @Test("Batch gradient computation with empty arrays")
    func batchGradientsEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let result = accelerator.computeGradientsBatch(a: [], b: [], c: [])
        
        #expect(result.d1.isEmpty)
        #expect(result.d2.isEmpty)
        #expect(result.d3.isEmpty)
    }
    
    @Test("Batch gradient computation with single element")
    func batchGradientsSingle() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let result = accelerator.computeGradientsBatch(a: [10], b: [20], c: [15])
        
        #expect(result.d1 == [5])
        #expect(result.d2 == [-5])
        #expect(result.d3 == [5])
    }
    
    @Test("Batch gradient computation with large arrays")
    func batchGradientsLarge() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let count = 1000
        let a = Array(repeating: 100, count: count)
        let b = Array(repeating: 150, count: count)
        let c = Array(repeating: 120, count: count)
        
        let result = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        #expect(result.d1.count == count)
        #expect(result.d2.count == count)
        #expect(result.d3.count == count)
        
        // D1 = b - c = 150 - 120 = 30
        #expect(result.d1.allSatisfy { $0 == 30 })
        
        // D2 = a - c = 100 - 120 = -20
        #expect(result.d2.allSatisfy { $0 == -20 })
        
        // D3 = c - a = 120 - 100 = 20
        #expect(result.d3.allSatisfy { $0 == 20 })
    }
    
    // MARK: - Statistical Analysis Tests
    
    @Test("Compute mean of values")
    func computeMean() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [10, 20, 30, 40, 50]
        let mean = accelerator.computeMean(values: values)
        
        #expect(abs(mean - 30.0) < 0.001)
    }
    
    @Test("Compute mean with empty array")
    func computeMeanEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let mean = accelerator.computeMean(values: [])
        #expect(mean == 0.0)
    }
    
    @Test("Compute mean with single value")
    func computeMeanSingle() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let mean = accelerator.computeMean(values: [42])
        #expect(abs(mean - 42.0) < 0.001)
    }
    
    @Test("Compute variance of values")
    func computeVariance() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [10, 20, 30, 40, 50]
        let variance = accelerator.computeVariance(values: values)
        
        // Expected variance: ((10-30)^2 + (20-30)^2 + (30-30)^2 + (40-30)^2 + (50-30)^2) / 4
        // = (400 + 100 + 0 + 100 + 400) / 4 = 1000 / 4 = 250
        #expect(abs(variance - 250.0) < 0.001)
    }
    
    @Test("Compute variance with two values")
    func computeVarianceTwoValues() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [10, 20]
        let variance = accelerator.computeVariance(values: values)
        
        // Expected variance: ((10-15)^2 + (20-15)^2) / 1 = (25 + 25) / 1 = 50
        #expect(abs(variance - 50.0) < 0.001)
    }
    
    @Test("Compute variance with single value returns zero")
    func computeVarianceSingle() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let variance = accelerator.computeVariance(values: [42])
        #expect(variance == 0.0)
    }
    
    @Test("Compute standard deviation")
    func computeStdDev() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [10, 20, 30, 40, 50]
        let stdDev = accelerator.computeStandardDeviation(values: values)
        
        // Expected std dev: sqrt(250) ≈ 15.811
        #expect(abs(stdDev - 15.811) < 0.01)
    }
    
    @Test("Compute min and max values")
    func computeMinMax() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [30, 10, 50, 20, 40]
        let (min, max) = accelerator.computeMinMax(values: values)
        
        #expect(min == 10)
        #expect(max == 50)
    }
    
    @Test("Compute min and max with single value")
    func computeMinMaxSingle() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let (min, max) = accelerator.computeMinMax(values: [42])
        
        #expect(min == 42)
        #expect(max == 42)
    }
    
    @Test("Compute min and max with empty array")
    func computeMinMaxEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let (min, max) = accelerator.computeMinMax(values: [])
        
        #expect(min == 0)
        #expect(max == 0)
    }
    
    // MARK: - Histogram Tests
    
    @Test("Compute histogram with uniform distribution")
    func histogramUniform() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // Values 0-9, each appearing once
        let pixels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let histogram = accelerator.computeHistogram(
            pixels: pixels,
            binCount: 10,
            minValue: 0,
            maxValue: 10
        )
        
        #expect(histogram.count == 10)
        // Each bin should have 1 value (approximately uniform)
        #expect(histogram.allSatisfy { $0 == 1 })
    }
    
    @Test("Compute histogram with concentrated values")
    func histogramConcentrated() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        // All values in middle range
        let pixels = [50, 51, 52, 53, 54, 55]
        let histogram = accelerator.computeHistogram(
            pixels: pixels,
            binCount: 10,
            minValue: 0,
            maxValue: 100
        )
        
        #expect(histogram.count == 10)
        // Most bins should be empty except bin 5 (50-59 range)
        #expect(histogram[5] == 6)
    }
    
    @Test("Compute histogram with empty pixels")
    func histogramEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let histogram = accelerator.computeHistogram(
            pixels: [],
            binCount: 10,
            minValue: 0,
            maxValue: 100
        )
        
        #expect(histogram.count == 10)
        #expect(histogram.allSatisfy { $0 == 0 })
    }
    
    @Test("Compute histogram with out-of-range values")
    func histogramOutOfRange() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let pixels = [-10, 0, 50, 100, 150]
        let histogram = accelerator.computeHistogram(
            pixels: pixels,
            binCount: 10,
            minValue: 0,
            maxValue: 100
        )
        
        #expect(histogram.count == 10)
        // Only values 0, 50, 100 should be counted
        let totalCount = histogram.reduce(0, +)
        #expect(totalCount == 3)
    }
    
    @Test("Compute histogram with single bin")
    func histogramSingleBin() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let pixels = [0, 50, 100, 25, 75]
        let histogram = accelerator.computeHistogram(
            pixels: pixels,
            binCount: 1,
            minValue: 0,
            maxValue: 100
        )
        
        #expect(histogram.count == 1)
        #expect(histogram[0] == 5)  // All values in one bin
    }
    
    // MARK: - Batch Vector Operations Tests
    
    @Test("Add two arrays element-wise")
    func addArrays() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 20, 30]
        let b = [5, 10, 15]
        let result = accelerator.addArrays(a: a, b: b)
        
        #expect(result == [15, 30, 45])
    }
    
    @Test("Add arrays with zero values")
    func addArraysZero() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 20, 30]
        let b = [0, 0, 0]
        let result = accelerator.addArrays(a: a, b: b)
        
        #expect(result == [10, 20, 30])
    }
    
    @Test("Add empty arrays")
    func addArraysEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let result = accelerator.addArrays(a: [], b: [])
        
        #expect(result.isEmpty)
    }
    
    @Test("Subtract two arrays element-wise")
    func subtractArrays() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [30, 40, 50]
        let b = [10, 20, 30]
        let result = accelerator.subtractArrays(a: a, b: b)
        
        #expect(result == [20, 20, 20])
    }
    
    @Test("Subtract arrays resulting in negative values")
    func subtractArraysNegative() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 20, 30]
        let b = [20, 30, 40]
        let result = accelerator.subtractArrays(a: a, b: b)
        
        #expect(result == [-10, -10, -10])
    }
    
    @Test("Subtract arrays with zero result")
    func subtractArraysZero() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let a = [10, 20, 30]
        let b = [10, 20, 30]
        let result = accelerator.subtractArrays(a: a, b: b)
        
        #expect(result == [0, 0, 0])
    }
    
    @Test("Multiply array by positive scalar")
    func multiplyByScalarPositive() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let array = [10, 20, 30]
        let result = accelerator.multiplyByScalar(array: array, scalar: 3)
        
        #expect(result == [30, 60, 90])
    }
    
    @Test("Multiply array by zero scalar")
    func multiplyByScalarZero() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let array = [10, 20, 30]
        let result = accelerator.multiplyByScalar(array: array, scalar: 0)
        
        #expect(result == [0, 0, 0])
    }
    
    @Test("Multiply array by negative scalar")
    func multiplyByScalarNegative() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let array = [10, 20, 30]
        let result = accelerator.multiplyByScalar(array: array, scalar: -2)
        
        #expect(result == [-20, -40, -60])
    }
    
    @Test("Multiply empty array by scalar")
    func multiplyByScalarEmpty() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let result = accelerator.multiplyByScalar(array: [], scalar: 5)
        
        #expect(result.isEmpty)
    }
    
    // MARK: - Integration Tests
    
    @Test("Batch gradients match scalar implementation")
    func batchGradientsMatchScalar() {
        let accelerateAccelerator = AccelerateFrameworkAccelerator()
        let scalarAccelerator = ScalarAccelerator()
        
        let a = [10, 50, 100, 25, 75]
        let b = [20, 40, 90, 30, 80]
        let c = [15, 45, 95, 27, 77]
        
        let batchResult = accelerateAccelerator.computeGradientsBatch(a: a, b: b, c: c)
        
        // Compare with scalar implementation
        for i in 0..<a.count {
            let scalarResult = scalarAccelerator.computeGradients(a: a[i], b: b[i], c: c[i])
            #expect(batchResult.d1[i] == scalarResult.d1)
            #expect(batchResult.d2[i] == scalarResult.d2)
            #expect(batchResult.d3[i] == scalarResult.d3)
        }
    }
    
    @Test("Statistical operations are consistent")
    func statisticalConsistency() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        
        let mean = accelerator.computeMean(values: values)
        let variance = accelerator.computeVariance(values: values)
        let stdDev = accelerator.computeStandardDeviation(values: values)
        let (min, max) = accelerator.computeMinMax(values: values)
        
        // Mean should be 55
        #expect(abs(mean - 55.0) < 0.001)
        
        // Min and max should match array bounds
        #expect(min == 10)
        #expect(max == 100)
        
        // Standard deviation should equal sqrt(variance)
        #expect(abs(stdDev - sqrt(variance)) < 0.001)
        
        // Standard deviation should be positive for non-constant values
        #expect(stdDev > 0)
    }
    
    @Test("Vector operations maintain array length")
    func vectorOperationsLength() {
        let accelerator = AccelerateFrameworkAccelerator()
        
        let count = 100
        let a = Array(0..<count)
        let b = Array(0..<count)
        
        let sum = accelerator.addArrays(a: a, b: b)
        let diff = accelerator.subtractArrays(a: a, b: b)
        let scaled = accelerator.multiplyByScalar(array: a, scalar: 2)
        
        #expect(sum.count == count)
        #expect(diff.count == count)
        #expect(scaled.count == count)
    }
}

#endif
