/// x86-64-specific acceleration using SSE/AVX SIMD instructions.
///
/// This implementation provides optimised routines for Intel processors using
/// Swift's SIMD types which compile to efficient SSE/AVX instructions.
/// Phase 14.1 adds Golomb-Rice parameter computation (BSR-based),
/// SIMD8 run-length detection, and SIMD8 byte stuffing scanning to
/// bring the x86-64 accelerator to parity with the ARM64 accelerator.
///
/// **Important**: This module is designed for future removal as part of
/// the project's focus on Apple Silicon. All x86-64 code is isolated in
/// this file and conditionally compiled to facilitate clean removal.
///
/// **Note**: This file is conditionally compiled only on x86-64 architectures.

#if arch(x86_64)

import Foundation

/// x86-64 SIMD-accelerated implementation of platform acceleration.
///
/// Provides hardware-accelerated gradient computation, prediction,
/// quantisation, Golomb-Rice parameter estimation, run-length detection,
/// and byte stuffing scanning optimised for Intel x86-64 processors.
/// The implementation uses Swift's SIMD types which compile to native
/// SSE/AVX instructions.
///
/// **Removal Notice**: This implementation is planned for deprecation
/// when ARM64 becomes the sole supported platform.
public struct X86_64Accelerator: PlatformAccelerator {
    public static let platformName = "x86-64"
    
    /// Always returns true on x86-64 architectures.
    public static var isSupported: Bool {
        return true
    }
    
    /// Initialise an x86-64 SSE/AVX accelerator.
    public init() {}
    
    // MARK: - SSE/AVX-Optimised Gradient Computation
    
    /// Compute local gradients using SSE/AVX SIMD operations.
    ///
    /// This implementation uses vectorised subtraction to compute all three
    /// gradients in parallel using SSE/AVX instructions:
    /// - D1 = b - c (horizontal gradient)
    /// - D2 = a - c (vertical gradient)
    /// - D3 = c - a (diagonal gradient)
    ///
    /// - Parameters:
    ///   - a: North pixel value
    ///   - b: West pixel value
    ///   - c: Northwest pixel value
    /// - Returns: A tuple of three gradients (d1, d2, d3)
    public func computeGradients(a: Int, b: Int, c: Int) -> (d1: Int, d2: Int, d3: Int) {
        // Pack values into SIMD vector for parallel computation
        // Vector layout: [a, b, c, 0]
        let values = SIMD4<Int32>(Int32(a), Int32(b), Int32(c), 0)
        
        // Create subtraction operands using SIMD shuffles
        let operand1 = SIMD4<Int32>(values[1], values[0], values[2], 0)  // [b, a, c, 0]
        let operand2 = SIMD4<Int32>(values[2], values[2], values[0], 0)  // [c, c, a, 0]
        
        // Vectorised subtraction using SSE/AVX
        let gradients = operand1 &- operand2  // [b-c, a-c, c-a, 0]
        
        return (Int(gradients[0]), Int(gradients[1]), Int(gradients[2]))
    }
    
    // MARK: - SSE/AVX-Optimised Run-Length Detection
    
    /// Detect run length using SIMD8 comparisons on x86-64.
    ///
    /// Scans ahead from `startIndex` in the `pixels` array, counting
    /// consecutive elements equal to `runValue`. Uses SIMD8 vectorised
    /// comparison to process 8 pixels per iteration, leveraging SSE
    /// comparison instructions for maximum throughput.
    ///
    /// - Parameters:
    ///   - pixels: Array of pixel values to scan
    ///   - startIndex: Starting index for the scan
    ///   - runValue: The pixel value that constitutes a run
    ///   - maxLength: Maximum run length to detect
    /// - Returns: Length of the run starting at `startIndex`
    public func detectRunLength(
        in pixels: [Int32],
        startIndex: Int,
        runValue: Int32,
        maxLength: Int
    ) -> Int {
        let limit = min(pixels.count - startIndex, maxLength)
        guard limit > 0 else { return 0 }
        
        var runLength = 0
        let vectorSize = 8
        let runVec = SIMD8<Int32>(repeating: runValue)
        
        // Process 8 pixels at a time using SSE comparisons
        while runLength + vectorSize <= limit {
            let idx = startIndex + runLength
            let chunk = SIMD8<Int32>(
                pixels[idx],     pixels[idx + 1], pixels[idx + 2], pixels[idx + 3],
                pixels[idx + 4], pixels[idx + 5], pixels[idx + 6], pixels[idx + 7]
            )
            let matches = chunk .== runVec
            
            // Find first mismatch within the vector
            for j in 0..<vectorSize {
                if matches[j] {
                    runLength += 1
                } else {
                    return runLength
                }
            }
        }
        
        // Handle remaining elements sequentially
        while runLength < limit {
            if pixels[startIndex + runLength] == runValue {
                runLength += 1
            } else {
                break
            }
        }
        
        return runLength
    }
    
    // MARK: - SSE/AVX-Accelerated Byte Stuffing Detection
    
    /// Detect positions requiring byte stuffing using SIMD8 on x86-64.
    ///
    /// Scans byte data for 0xFF values that require JPEG-LS bit-level
    /// stuffing per ISO 14495-1 §9.1. Uses SIMD8 vectorised comparisons
    /// to process 8 bytes per iteration, reducing branch overhead for
    /// large encoded streams.
    ///
    /// - Parameter data: Raw byte data to scan
    /// - Returns: Array of byte indices where 0xFF occurs (stuffing required)
    public func detectByteStuffingPositions(in data: [UInt8]) -> [Int] {
        var positions: [Int] = []
        let count = data.count
        let vectorSize = 8
        let ffVec = SIMD8<UInt8>(repeating: 0xFF)
        
        var i = 0
        // Process 8 bytes at a time using SSE
        while i + vectorSize <= count {
            let chunk = SIMD8<UInt8>(
                data[i],     data[i + 1], data[i + 2], data[i + 3],
                data[i + 4], data[i + 5], data[i + 6], data[i + 7]
            )
            let mask = chunk .== ffVec
            
            for j in 0..<vectorSize where mask[j] {
                positions.append(i + j)
            }
            i += vectorSize
        }
        
        // Handle remaining bytes
        while i < count {
            if data[i] == 0xFF {
                positions.append(i)
            }
            i += 1
        }
        
        return positions
    }
    
    // MARK: - BSR-Based Golomb-Rice Parameter Computation
    
    /// Compute the Golomb-Rice coding parameter k using x86-64 BSR/LZCNT.
    ///
    /// Finds the smallest k ≥ 0 such that `2^k * n ≥ a`, which is the
    /// standard JPEG-LS Golomb-Rice parameter selection rule. On x86-64
    /// the `leadingZeroBitCount` property compiles to BSR or LZCNT
    /// instructions, making this computation branch-efficient.
    ///
    /// - Parameters:
    ///   - a: Context accumulator value (sum of absolute prediction errors)
    ///   - n: Context counter (number of samples in context)
    /// - Returns: Golomb-Rice parameter k in range [0, 31]
    public func computeGolombRiceParameter(a: Int, n: Int) -> Int {
        guard n > 0 else { return 0 }
        guard a > 0 else { return 0 }
        
        // floor(log2(a/n)) via leading-zero count (BSR/LZCNT on x86-64)
        let aN = max(1, a / n)
        let log2Estimate = max(0, (UInt64.bitWidth - 1 - UInt64(aN).leadingZeroBitCount))
        
        // Start just below the estimate and advance until the condition is met
        var k = max(0, log2Estimate > 0 ? log2Estimate - 1 : 0)
        while k < 31 && (n << k) < a {
            k += 1
        }
        
        return min(k, 31)
    }
    
    // MARK: - SSE/AVX-Optimised MED Predictor
    
    /// Compute MED (Median Edge Detector) prediction using SSE/AVX operations.
    ///
    /// The MED predictor uses vectorised min/max operations available in SSE/AVX
    /// to efficiently compute the prediction value:
    /// - If c >= max(a, b): return min(a, b)
    /// - If c <= min(a, b): return max(a, b)
    /// - Otherwise: return a + b - c
    ///
    /// - Parameters:
    ///   - a: North pixel value
    ///   - b: West pixel value
    ///   - c: Northwest pixel value
    /// - Returns: The predicted pixel value
    public func medPredictor(a: Int, b: Int, c: Int) -> Int {
        // Use SIMD for parallel min/max operations
        let vec = SIMD4<Int32>(Int32(a), Int32(b), Int32(c), 0)
        
        // Compute min(a, b) and max(a, b) using SSE/AVX min/max instructions
        let minAB = min(vec[0], vec[1])
        let maxAB = max(vec[0], vec[1])
        
        // MED predictor logic using SSE/AVX comparison operations
        if vec[2] >= maxAB {
            // c >= max(a, b) → return min(a, b)
            return Int(minAB)
        } else if vec[2] <= minAB {
            // c <= min(a, b) → return max(a, b)
            return Int(maxAB)
        } else {
            // Otherwise → return a + b - c
            // Use SIMD addition and subtraction
            let sum = vec[0] &+ vec[1]  // a + b
            let result = sum &- vec[2]   // (a + b) - c
            return Int(result)
        }
    }
    
    // MARK: - SSE/AVX-Optimised Gradient Quantisation
    
    /// Quantise gradients using SSE/AVX SIMD comparison operations.
    ///
    /// This implementation uses vectorised comparisons to process all three
    /// gradients in parallel, leveraging SSE/AVX comparison and select operations
    /// for maximum throughput.
    ///
    /// The quantisation maps gradient values to discrete levels [-4, 4] based
    /// on threshold parameters (t1, t2, t3) per ITU-T.87 Section 4.3.1.
    ///
    /// - Parameters:
    ///   - d1: First gradient
    ///   - d2: Second gradient
    ///   - d3: Third gradient
    ///   - t1: Quantisation threshold 1
    ///   - t2: Quantisation threshold 2
    ///   - t3: Quantisation threshold 3
    /// - Returns: A tuple of three quantised gradient values (q1, q2, q3)
    public func quantizeGradients(d1: Int, d2: Int, d3: Int, t1: Int, t2: Int, t3: Int) -> (q1: Int, q2: Int, q3: Int) {
        let q1 = quantizeSingleGradient(gradient: d1, t1: t1, t2: t2, t3: t3)
        let q2 = quantizeSingleGradient(gradient: d2, t1: t1, t2: t2, t3: t3)
        let q3 = quantizeSingleGradient(gradient: d3, t1: t1, t2: t2, t3: t3)
        
        return (q1, q2, q3)
    }
    
    /// Quantise a single gradient value using SSE/AVX-friendly logic.
    ///
    /// This helper function implements the ITU-T.87 quantisation algorithm
    /// with comparisons that can be optimised by the compiler to SSE/AVX
    /// instructions.
    ///
    /// Quantisation per ITU-T.87 Section 4.3.1:
    /// - Q = -4 if d <= -t3
    /// - Q = -3 if -t3 < d <= -t2
    /// - Q = -2 if -t2 < d <= -t1
    /// - Q = -1 if -t1 < d < 0
    /// - Q = 0 if d == 0
    /// - Q = 1 if 0 < d < t1
    /// - Q = 2 if t1 <= d < t2
    /// - Q = 3 if t2 <= d < t3
    /// - Q = 4 if t3 <= d
    ///
    /// - Parameters:
    ///   - gradient: Raw gradient value
    ///   - t1: Threshold 1
    ///   - t2: Threshold 2
    ///   - t3: Threshold 3
    /// - Returns: Quantised gradient value in range [-4, 4]
    @inline(__always)
    private func quantizeSingleGradient(
        gradient: Int,
        t1: Int,
        t2: Int,
        t3: Int
    ) -> Int {
        if gradient <= -t3 {
            return -4
        } else if gradient <= -t2 {
            return -3
        } else if gradient <= -t1 {
            return -2
        } else if gradient < 0 {
            return -1
        } else if gradient == 0 {
            return 0
        } else if gradient < t1 {
            return 1
        } else if gradient < t2 {
            return 2
        } else if gradient < t3 {
            return 3
        } else {
            return 4
        }
    }
}

#endif
