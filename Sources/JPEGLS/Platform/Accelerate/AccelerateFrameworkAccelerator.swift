/// Apple Accelerate framework-based acceleration using vDSP.
///
/// This implementation leverages the Apple Accelerate framework for vectorized
/// batch operations on image data. The Accelerate framework provides highly
/// optimized implementations of common signal processing and mathematical
/// operations.
///
/// **Note**: This file is conditionally compiled only on Apple platforms where
/// the Accelerate framework is available (macOS, iOS, tvOS, watchOS).

#if canImport(Accelerate)

import Foundation
import Accelerate

/// Accelerate framework-based implementation for batch operations.
///
/// Provides hardware-accelerated batch gradient computation, statistical
/// analysis, and histogram operations optimized for Apple platforms using
/// the vDSP (vector Digital Signal Processing) library.
///
/// Unlike the ARM64Accelerator which optimizes single-pixel operations,
/// this accelerator focuses on batch operations across multiple pixels
/// to leverage vDSP's highly optimized array processing capabilities.
public struct AccelerateFrameworkAccelerator: Sendable {
    public static let platformName = "Accelerate"
    
    /// Returns true if the Accelerate framework is available.
    public static var isSupported: Bool {
        return true
    }
    
    /// Initialize an Accelerate framework accelerator
    public init() {}
    
    // MARK: - Batch Gradient Computation
    
    /// Compute gradients for a batch of pixels using vDSP operations.
    ///
    /// This function uses Accelerate's vectorized subtraction operations to
    /// compute gradients for multiple pixels simultaneously, providing
    /// significant performance improvements for large image regions.
    ///
    /// For each pixel position i:
    /// - D1[i] = b[i] - c[i] (horizontal gradient)
    /// - D2[i] = a[i] - c[i] (vertical gradient)  
    /// - D3[i] = c[i] - a[i] (diagonal gradient)
    ///
    /// - Parameters:
    ///   - a: Array of north pixel values
    ///   - b: Array of west pixel values
    ///   - c: Array of northwest pixel values
    /// - Returns: A tuple of three arrays containing the computed gradients (d1, d2, d3)
    /// - Precondition: All arrays must have the same length
    public func computeGradientsBatch(
        a: [Int],
        b: [Int],
        c: [Int]
    ) -> (d1: [Int], d2: [Int], d3: [Int]) {
        precondition(a.count == b.count && b.count == c.count, "Arrays must have same length")
        
        let count = a.count
        guard count > 0 else {
            return ([], [], [])
        }
        
        // Convert Int arrays to Float for vDSP operations
        let aFloat = a.map { Float($0) }
        let bFloat = b.map { Float($0) }
        let cFloat = c.map { Float($0) }
        
        var d1Float = [Float](repeating: 0, count: count)
        var d2Float = [Float](repeating: 0, count: count)
        var d3Float = [Float](repeating: 0, count: count)
        
        // D1 = b - c (vectorized subtraction)
        vDSP_vsub(cFloat, 1, bFloat, 1, &d1Float, 1, vDSP_Length(count))
        
        // D2 = a - c (vectorized subtraction)
        vDSP_vsub(cFloat, 1, aFloat, 1, &d2Float, 1, vDSP_Length(count))
        
        // D3 = c - a (vectorized subtraction)
        vDSP_vsub(aFloat, 1, cFloat, 1, &d3Float, 1, vDSP_Length(count))
        
        // Convert back to Int
        let d1 = d1Float.map { Int($0) }
        let d2 = d2Float.map { Int($0) }
        let d3 = d3Float.map { Int($0) }
        
        return (d1, d2, d3)
    }
    
    // MARK: - Statistical Analysis
    
    /// Compute histogram of pixel values using Accelerate.
    ///
    /// This function uses vDSP to efficiently compute a histogram of pixel
    /// values, which can be useful for analyzing image characteristics and
    /// parameter tuning.
    ///
    /// - Parameters:
    ///   - pixels: Array of pixel values
    ///   - binCount: Number of histogram bins
    ///   - minValue: Minimum value for histogram range
    ///   - maxValue: Maximum value for histogram range
    /// - Returns: Array of histogram bin counts
    public func computeHistogram(
        pixels: [Int],
        binCount: Int,
        minValue: Int,
        maxValue: Int
    ) -> [Int] {
        guard !pixels.isEmpty && binCount > 0 && minValue < maxValue else {
            return Array(repeating: 0, count: binCount)
        }
        
        // Convert to Float for vDSP operations
        let pixelsFloat = pixels.map { Float($0) }
        
        // Create histogram bins
        var histogram = [vDSP_Length](repeating: 0, count: binCount)
        
        // Compute histogram using vDSP
        // Note: vDSP_vhist is available but requires specific setup
        // For now, use a manual binning approach optimized with vDSP operations
        let range = Float(maxValue - minValue)
        let binWidth = range / Float(binCount)
        
        for value in pixelsFloat {
            let normalizedValue = value - Float(minValue)
            if normalizedValue >= 0 && normalizedValue <= range {
                let binIndex = min(Int(normalizedValue / binWidth), binCount - 1)
                histogram[binIndex] += 1
            }
        }
        
        return histogram.map { Int($0) }
    }
    
    /// Compute mean value of an array using vDSP.
    ///
    /// - Parameter values: Array of values
    /// - Returns: The mean value
    public func computeMean(values: [Int]) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }
        
        let valuesFloat = values.map { Float($0) }
        var mean: Float = 0
        
        vDSP_meanv(valuesFloat, 1, &mean, vDSP_Length(values.count))
        
        return Double(mean)
    }
    
    /// Compute variance of an array using vDSP.
    ///
    /// - Parameter values: Array of values
    /// - Returns: The variance value
    public func computeVariance(values: [Int]) -> Double {
        guard values.count > 1 else {
            return 0.0
        }
        
        let valuesFloat = values.map { Float($0) }
        var mean: Float = 0
        var variance: Float = 0
        
        // Compute mean
        vDSP_meanv(valuesFloat, 1, &mean, vDSP_Length(values.count))
        
        // Compute variance: sum of (x - mean)^2 / (n - 1)
        var differences = [Float](repeating: 0, count: values.count)
        var meanArray = [Float](repeating: mean, count: values.count)
        
        // differences = values - mean
        vDSP_vsub(meanArray, 1, valuesFloat, 1, &differences, 1, vDSP_Length(values.count))
        
        // square the differences
        var squaredDifferences = [Float](repeating: 0, count: values.count)
        vDSP_vsq(differences, 1, &squaredDifferences, 1, vDSP_Length(values.count))
        
        // sum the squared differences
        var sum: Float = 0
        vDSP_sve(squaredDifferences, 1, &sum, vDSP_Length(values.count))
        
        // divide by (n - 1) for sample variance
        variance = sum / Float(values.count - 1)
        
        return Double(variance)
    }
    
    /// Compute standard deviation of an array using vDSP.
    ///
    /// - Parameter values: Array of values
    /// - Returns: The standard deviation value
    public func computeStandardDeviation(values: [Int]) -> Double {
        return sqrt(computeVariance(values: values))
    }
    
    /// Compute minimum and maximum values using vDSP.
    ///
    /// - Parameter values: Array of values
    /// - Returns: A tuple containing (min, max)
    public func computeMinMax(values: [Int]) -> (min: Int, max: Int) {
        guard !values.isEmpty else {
            return (0, 0)
        }
        
        let valuesFloat = values.map { Float($0) }
        var min: Float = 0
        var max: Float = 0
        
        vDSP_minv(valuesFloat, 1, &min, vDSP_Length(values.count))
        vDSP_maxv(valuesFloat, 1, &max, vDSP_Length(values.count))
        
        return (Int(min), Int(max))
    }
    
    // MARK: - Batch Vector Operations
    
    /// Add two arrays element-wise using vDSP.
    ///
    /// - Parameters:
    ///   - a: First array
    ///   - b: Second array
    /// - Returns: Array containing element-wise sum
    /// - Precondition: Arrays must have the same length
    public func addArrays(a: [Int], b: [Int]) -> [Int] {
        precondition(a.count == b.count, "Arrays must have same length")
        
        guard !a.isEmpty else {
            return []
        }
        
        let aFloat = a.map { Float($0) }
        let bFloat = b.map { Float($0) }
        var result = [Float](repeating: 0, count: a.count)
        
        vDSP_vadd(aFloat, 1, bFloat, 1, &result, 1, vDSP_Length(a.count))
        
        return result.map { Int($0) }
    }
    
    /// Subtract two arrays element-wise using vDSP.
    ///
    /// - Parameters:
    ///   - a: First array
    ///   - b: Second array (subtracted from first)
    /// - Returns: Array containing element-wise difference (a - b)
    /// - Precondition: Arrays must have the same length
    public func subtractArrays(a: [Int], b: [Int]) -> [Int] {
        precondition(a.count == b.count, "Arrays must have same length")
        
        guard !a.isEmpty else {
            return []
        }
        
        let aFloat = a.map { Float($0) }
        let bFloat = b.map { Float($0) }
        var result = [Float](repeating: 0, count: a.count)
        
        vDSP_vsub(bFloat, 1, aFloat, 1, &result, 1, vDSP_Length(a.count))
        
        return result.map { Int($0) }
    }
    
    /// Multiply array by a scalar using vDSP.
    ///
    /// - Parameters:
    ///   - array: Input array
    ///   - scalar: Scalar multiplier
    /// - Returns: Array with each element multiplied by scalar
    public func multiplyByScalar(array: [Int], scalar: Int) -> [Int] {
        guard !array.isEmpty else {
            return []
        }
        
        let arrayFloat = array.map { Float($0) }
        var scalarFloat = Float(scalar)
        var result = [Float](repeating: 0, count: array.count)
        
        vDSP_vsmul(arrayFloat, 1, &scalarFloat, &result, 1, vDSP_Length(array.count))
        
        return result.map { Int($0) }
    }
    
    // MARK: - vDSP-Accelerated Prediction Error Computation
    
    /// Compute prediction errors for a batch of pixels using vDSP.
    ///
    /// For each pixel i, computes: error[i] = actual[i] - predicted[i]
    ///
    /// Uses `vDSP_vsub` for vectorised subtraction over the entire batch,
    /// avoiding per-element overhead for large images.
    ///
    /// - Parameters:
    ///   - actual: Array of actual pixel values
    ///   - predicted: Array of predicted pixel values
    /// - Returns: Array of prediction errors
    /// - Precondition: Both arrays must have the same length
    public func computePredictionErrors(actual: [Int], predicted: [Int]) -> [Int] {
        return subtractArrays(a: actual, b: predicted)
    }
    
    /// Compute absolute prediction errors for a batch using vDSP.
    ///
    /// For each pixel i, computes: absError[i] = |actual[i] - predicted[i]|
    ///
    /// Uses `vDSP_vsub` followed by `vDSP_vabs` to vectorise both steps.
    ///
    /// - Parameters:
    ///   - actual: Array of actual pixel values
    ///   - predicted: Array of predicted pixel values
    /// - Returns: Array of absolute prediction errors
    /// - Precondition: Both arrays must have the same length
    public func computeAbsolutePredictionErrors(actual: [Int], predicted: [Int]) -> [Int] {
        precondition(actual.count == predicted.count, "Arrays must have same length")
        
        let count = actual.count
        guard count > 0 else { return [] }
        
        let actualFloat = actual.map { Float($0) }
        let predictedFloat = predicted.map { Float($0) }
        
        var errorFloat = [Float](repeating: 0, count: count)
        var absErrorFloat = [Float](repeating: 0, count: count)
        
        // errors = actual - predicted
        vDSP_vsub(predictedFloat, 1, actualFloat, 1, &errorFloat, 1, vDSP_Length(count))
        
        // absErrors = |errors|
        vDSP_vabs(errorFloat, 1, &absErrorFloat, 1, vDSP_Length(count))
        
        return absErrorFloat.map { Int($0) }
    }
    
    // MARK: - vDSP-Accelerated Context State Updates
    
    /// Batch-update context accumulator A using vDSP absolute-value sum.
    ///
    /// Accumulates |error| into each context's A value. Where contexts are
    /// sparse (many different contexts per image line), the scatter step is
    /// sequential; the absolute-value computation over all errors is vectorised
    /// using `vDSP_vabs`.
    ///
    /// - Parameters:
    ///   - aArray: Context accumulator array A (modified in place)
    ///   - errors: Signed prediction errors for each pixel
    ///   - contextIndices: Context index for each pixel (parallel to `errors`)
    public func updateAccumulatorA(
        aArray: inout [Int],
        errors: [Int],
        contextIndices: [Int]
    ) {
        precondition(errors.count == contextIndices.count, "Arrays must have same length")
        
        guard !errors.isEmpty else { return }
        
        // Compute absolute values directly using Swift integer abs to avoid
        // Float conversion overhead and floating-point rounding artefacts.
        for i in 0..<errors.count {
            aArray[contextIndices[i]] += abs(errors[i])
        }
    }
    
    /// Batch-update context bias accumulator B using vDSP.
    ///
    /// Accumulates the signed prediction error into each context's B value.
    /// The scatter step is sequential; the sign of each error is used directly.
    ///
    /// - Parameters:
    ///   - bArray: Context bias accumulator array B (modified in place)
    ///   - errors: Signed prediction errors for each pixel
    ///   - contextIndices: Context index for each pixel (parallel to `errors`)
    public func updateAccumulatorB(
        bArray: inout [Int],
        errors: [Int],
        contextIndices: [Int]
    ) {
        precondition(errors.count == contextIndices.count, "Arrays must have same length")
        
        for i in 0..<errors.count {
            bArray[contextIndices[i]] += errors[i]
        }
    }
    
    // MARK: - Pixel Buffer Format Conversions
    
    /// Convert a planar pixel buffer to interleaved format.
    ///
    /// Rearranges pixel data from per-component planar layout
    /// ([component][row × col]) to interleaved layout ([row × col × component]).
    ///
    /// - Parameters:
    ///   - planes: Array of component planes; each plane is a flat `[UInt8]`
    ///             in row-major order with `width × height` elements
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: Interleaved byte array with `width × height × componentCount` elements
    public func planesToInterleaved(planes: [[UInt8]], width: Int, height: Int) -> [UInt8] {
        let componentCount = planes.count
        guard componentCount > 0, width > 0, height > 0 else { return [] }
        
        let pixelCount = width * height
        guard planes.allSatisfy({ $0.count == pixelCount }) else {
            preconditionFailure("Each plane must contain exactly width × height bytes")
        }
        
        if componentCount == 1 {
            return planes[0]
        }
        
        var interleaved = [UInt8](repeating: 0, count: pixelCount * componentCount)
        
        for p in 0..<componentCount {
            let plane = planes[p]
            for i in 0..<pixelCount {
                interleaved[i * componentCount + p] = plane[i]
            }
        }
        
        return interleaved
    }
    
    /// Convert an interleaved pixel buffer to planar format.
    ///
    /// Rearranges pixel data from interleaved layout ([row × col × component])
    /// to per-component planar layout ([component][row × col]).
    ///
    /// - Parameters:
    ///   - interleaved: Interleaved byte array with `width × height × componentCount` elements
    ///   - componentCount: Number of colour components
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: Array of planar byte arrays, one per component
    public func interleavedToPlanes(
        interleaved: [UInt8],
        componentCount: Int,
        width: Int,
        height: Int
    ) -> [[UInt8]] {
        guard componentCount > 0, width > 0, height > 0 else { return [] }
        
        let pixelCount = width * height
        guard interleaved.count == pixelCount * componentCount else {
            preconditionFailure("Interleaved buffer size must equal width × height × componentCount")
        }
        
        if componentCount == 1 {
            return [interleaved]
        }
        
        var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: pixelCount), count: componentCount)
        
        for i in 0..<pixelCount {
            for p in 0..<componentCount {
                planes[p][i] = interleaved[i * componentCount + p]
            }
        }
        
        return planes
    }
    
    // MARK: - Accelerate-Based Colour Space Transformations
    
    /// Apply HP1 forward colour transform to a batch of RGB pixels using vDSP.
    ///
    /// HP1 forward transform (lossless, reversible):
    /// - G′ = G  (unchanged)
    /// - R′ = R − G
    /// - B′ = B − G
    ///
    /// Uses `vDSP_vsub` for vectorised subtraction over the entire pixel batch.
    ///
    /// - Parameters:
    ///   - r: Red component values
    ///   - g: Green component values
    ///   - b: Blue component values
    /// - Returns: Transformed (r′, g′, b′) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP1Forward(r: [Int], g: [Int], b: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        
        let rFloat = r.map { Float($0) }
        let gFloat = g.map { Float($0) }
        let bFloat = b.map { Float($0) }
        
        var rPrime = [Float](repeating: 0, count: count)
        var bPrime = [Float](repeating: 0, count: count)
        
        // R′ = R − G
        vDSP_vsub(gFloat, 1, rFloat, 1, &rPrime, 1, vDSP_Length(count))
        // B′ = B − G
        vDSP_vsub(gFloat, 1, bFloat, 1, &bPrime, 1, vDSP_Length(count))
        
        return (rPrime.map { Int($0) }, g, bPrime.map { Int($0) })
    }
    
    /// Apply HP1 inverse colour transform to a batch of transformed pixels using vDSP.
    ///
    /// HP1 inverse transform:
    /// - G = G′
    /// - R = R′ + G′
    /// - B = B′ + G′
    ///
    /// - Parameters:
    ///   - rPrime: Transformed red component values
    ///   - gPrime: Transformed green component values (unchanged)
    ///   - bPrime: Transformed blue component values
    /// - Returns: Recovered (r, g, b) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP1Inverse(rPrime: [Int], gPrime: [Int], bPrime: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(rPrime.count == gPrime.count && gPrime.count == bPrime.count, "Arrays must have same length")
        
        let count = rPrime.count
        guard count > 0 else { return ([], [], []) }
        
        let rPrimeFloat = rPrime.map { Float($0) }
        let gPrimeFloat = gPrime.map { Float($0) }
        let bPrimeFloat = bPrime.map { Float($0) }
        
        var r = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)
        
        // R = R′ + G′
        vDSP_vadd(rPrimeFloat, 1, gPrimeFloat, 1, &r, 1, vDSP_Length(count))
        // B = B′ + G′
        vDSP_vadd(bPrimeFloat, 1, gPrimeFloat, 1, &b, 1, vDSP_Length(count))
        
        return (r.map { Int($0) }, gPrime, b.map { Int($0) })
    }
    
    /// Apply HP2 forward colour transform to a batch of RGB pixels using vDSP.
    ///
    /// HP2 forward transform (lossless, reversible):
    /// - G′ = G
    /// - R′ = R − G
    /// - B′ = B − ((R + G) >> 1)
    ///
    /// Note: The arithmetic right-shift step is computed per-element after the
    /// vDSP vectorised addition, since integer right-shift cannot be expressed
    /// directly as a vDSP primitive.
    ///
    /// - Parameters:
    ///   - r: Red component values
    ///   - g: Green component values
    ///   - b: Blue component values
    /// - Returns: Transformed (r′, g′, b′) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP2Forward(r: [Int], g: [Int], b: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        
        let rFloat = r.map { Float($0) }
        let gFloat = g.map { Float($0) }
        let bFloat = b.map { Float($0) }
        
        var rPrime = [Float](repeating: 0, count: count)
        var rPlusG  = [Float](repeating: 0, count: count)
        
        // R′ = R − G
        vDSP_vsub(gFloat, 1, rFloat, 1, &rPrime, 1, vDSP_Length(count))
        
        // R + G (for the B′ formula)
        vDSP_vadd(rFloat, 1, gFloat, 1, &rPlusG, 1, vDSP_Length(count))
        
        // B′ = B − ((R + G) >> 1)  — integer arithmetic shift
        let bPrime = zip(bFloat, rPlusG).map { bVal, rgVal in
            Int(bVal) - (Int(rgVal) >> 1)
        }
        
        return (rPrime.map { Int($0) }, g, bPrime)
    }
    
    /// Apply HP2 inverse colour transform to a batch of transformed pixels using vDSP.
    ///
    /// HP2 inverse transform:
    /// - G = G′
    /// - R = R′ + G′
    /// - B = B′ + ((R + G) >> 1)
    ///
    /// - Parameters:
    ///   - rPrime: Transformed red component values
    ///   - gPrime: Transformed green component values (unchanged)
    ///   - bPrime: Transformed blue component values
    /// - Returns: Recovered (r, g, b) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP2Inverse(rPrime: [Int], gPrime: [Int], bPrime: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(rPrime.count == gPrime.count && gPrime.count == bPrime.count, "Arrays must have same length")
        
        let count = rPrime.count
        guard count > 0 else { return ([], [], []) }
        
        let rPrimeFloat = rPrime.map { Float($0) }
        let gPrimeFloat = gPrime.map { Float($0) }
        
        var r = [Float](repeating: 0, count: count)
        
        // R = R′ + G′
        vDSP_vadd(rPrimeFloat, 1, gPrimeFloat, 1, &r, 1, vDSP_Length(count))
        
        let rInt = r.map { Int($0) }
        
        // B = B′ + ((R + G) >> 1)
        let b = zip(bPrime, zip(rInt, gPrime)).map { bVal, rg in
            bVal + ((rg.0 + rg.1) >> 1)
        }
        
        return (rInt, gPrime, b)
    }
    
    /// Apply HP3 forward colour transform to a batch of RGB pixels using vDSP.
    ///
    /// HP3 forward transform (lossless, reversible):
    /// - B′ = B
    /// - R′ = R − B
    /// - G′ = G − ((R + B) >> 1)
    ///
    /// - Parameters:
    ///   - r: Red component values
    ///   - g: Green component values
    ///   - b: Blue component values
    /// - Returns: Transformed (r′, g′, b′) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP3Forward(r: [Int], g: [Int], b: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        
        let rFloat = r.map { Float($0) }
        let gFloat = g.map { Float($0) }
        let bFloat = b.map { Float($0) }
        
        var rPrime = [Float](repeating: 0, count: count)
        var rPlusB  = [Float](repeating: 0, count: count)
        
        // R′ = R − B
        vDSP_vsub(bFloat, 1, rFloat, 1, &rPrime, 1, vDSP_Length(count))
        
        // R + B
        vDSP_vadd(rFloat, 1, bFloat, 1, &rPlusB, 1, vDSP_Length(count))
        
        // G′ = G − ((R + B) >> 1)
        let gPrime = zip(gFloat, rPlusB).map { gVal, rbVal in
            Int(gVal) - (Int(rbVal) >> 1)
        }
        
        return (rPrime.map { Int($0) }, gPrime, b)
    }
    
    /// Apply HP3 inverse colour transform to a batch of transformed pixels using vDSP.
    ///
    /// HP3 inverse transform:
    /// - B = B′
    /// - R = R′ + B′
    /// - G = G′ + ((R + B) >> 1)
    ///
    /// - Parameters:
    ///   - rPrime: Transformed red component values
    ///   - gPrime: Transformed green component values
    ///   - bPrime: Transformed blue component values (unchanged)
    /// - Returns: Recovered (r, g, b) components as integer arrays
    /// - Precondition: All arrays must have the same length
    public func applyHP3Inverse(rPrime: [Int], gPrime: [Int], bPrime: [Int]) -> (r: [Int], g: [Int], b: [Int]) {
        precondition(rPrime.count == gPrime.count && gPrime.count == bPrime.count, "Arrays must have same length")
        
        let count = rPrime.count
        guard count > 0 else { return ([], [], []) }
        
        let rPrimeFloat = rPrime.map { Float($0) }
        let bPrimeFloat = bPrime.map { Float($0) }
        
        var r = [Float](repeating: 0, count: count)
        
        // R = R′ + B′
        vDSP_vadd(rPrimeFloat, 1, bPrimeFloat, 1, &r, 1, vDSP_Length(count))
        
        let rInt = r.map { Int($0) }
        
        // G = G′ + ((R + B) >> 1)
        let g = zip(gPrime, zip(rInt, bPrime)).map { gVal, rb in
            gVal + ((rb.0 + rb.1) >> 1)
        }
        
        return (rInt, g, bPrime)
    }
}

#endif
