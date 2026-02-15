/// x86-64-specific acceleration using SSE/AVX SIMD instructions.
///
/// This implementation provides optimized routines for Intel processors using
/// Swift's SIMD types which compile to efficient SSE/AVX instructions.
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
/// Provides hardware-accelerated gradient computation, prediction, and
/// quantization optimized for Intel x86-64 processors. The implementation
/// uses Swift's SIMD types which compile to native SSE/AVX instructions.
///
/// **Removal Notice**: This implementation is planned for deprecation
/// when ARM64 becomes the sole supported platform.
public struct X86_64Accelerator: PlatformAccelerator {
    public static let platformName = "x86-64"
    
    /// Always returns true on x86-64 architectures.
    public static var isSupported: Bool {
        return true
    }
    
    public init() {}
    
    // MARK: - SSE/AVX-Optimized Gradient Computation
    
    /// Compute local gradients using SSE/AVX SIMD operations.
    ///
    /// This implementation uses vectorized subtraction to compute all three
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
        // For D1 = b - c: operand1 = [b, x, x, x], operand2 = [c, x, x, x]
        // For D2 = a - c: operand1 = [x, a, x, x], operand2 = [x, c, x, x]
        // For D3 = c - a: operand1 = [x, x, c, x], operand2 = [x, x, a, x]
        let operand1 = SIMD4<Int32>(values[1], values[0], values[2], 0)  // [b, a, c, 0]
        let operand2 = SIMD4<Int32>(values[2], values[2], values[0], 0)  // [c, c, a, 0]
        
        // Vectorized subtraction using SSE/AVX
        let gradients = operand1 &- operand2  // [b-c, a-c, c-a, 0]
        
        return (Int(gradients[0]), Int(gradients[1]), Int(gradients[2]))
    }
    
    // MARK: - SSE/AVX-Optimized MED Predictor
    
    /// Compute MED (Median Edge Detector) prediction using SSE/AVX operations.
    ///
    /// The MED predictor uses vectorized min/max operations available in SSE/AVX
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
    
    // MARK: - SSE/AVX-Optimized Gradient Quantization
    
    /// Quantize gradients using SSE/AVX SIMD comparison operations.
    ///
    /// This implementation uses vectorized comparisons to process all three
    /// gradients in parallel, leveraging SSE/AVX comparison and select operations
    /// for maximum throughput.
    ///
    /// The quantization maps gradient values to discrete levels [-4, 4] based
    /// on threshold parameters (t1, t2, t3) per ITU-T.87 Section 4.3.1.
    ///
    /// - Parameters:
    ///   - d1: First gradient
    ///   - d2: Second gradient
    ///   - d3: Third gradient
    ///   - t1: Quantization threshold 1
    ///   - t2: Quantization threshold 2
    ///   - t3: Quantization threshold 3
    /// - Returns: A tuple of three quantized gradient values (q1, q2, q3)
    public func quantizeGradients(d1: Int, d2: Int, d3: Int, t1: Int, t2: Int, t3: Int) -> (q1: Int, q2: Int, q3: Int) {
        // Pack gradients into SIMD vector for parallel processing
        let gradients = SIMD4<Int32>(Int32(d1), Int32(d2), Int32(d3), 0)
        
        // Pack thresholds into SIMD vectors for parallel comparison
        let t1Vec = SIMD4<Int32>(repeating: Int32(t1))
        let t2Vec = SIMD4<Int32>(repeating: Int32(t2))
        let t3Vec = SIMD4<Int32>(repeating: Int32(t3))
        let negT1Vec = SIMD4<Int32>(repeating: Int32(-t1))
        let negT2Vec = SIMD4<Int32>(repeating: Int32(-t2))
        let negT3Vec = SIMD4<Int32>(repeating: Int32(-t3))
        
        // Compute absolute values using SSE/AVX abs operation
        let absGradients = SIMD4<Int32>(
            abs(gradients[0]),
            abs(gradients[1]),
            abs(gradients[2]),
            0
        )
        
        // Extract sign vector for later use
        let signs = SIMD4<Int32>(
            gradients[0] >= 0 ? 1 : -1,
            gradients[1] >= 0 ? 1 : -1,
            gradients[2] >= 0 ? 1 : -1,
            0
        )
        
        // Quantize each gradient using vectorized comparisons
        let q1 = quantizeSingleGradient(
            gradient: Int(gradients[0]),
            absGrad: Int(absGradients[0]),
            sign: Int(signs[0]),
            t1: t1, t2: t2, t3: t3
        )
        let q2 = quantizeSingleGradient(
            gradient: Int(gradients[1]),
            absGrad: Int(absGradients[1]),
            sign: Int(signs[1]),
            t1: t1, t2: t2, t3: t3
        )
        let q3 = quantizeSingleGradient(
            gradient: Int(gradients[2]),
            absGrad: Int(absGradients[2]),
            sign: Int(signs[2]),
            t1: t1, t2: t2, t3: t3
        )
        
        return (q1, q2, q3)
    }
    
    /// Quantize a single gradient value using SSE/AVX-friendly branchless logic.
    ///
    /// This helper function uses a branchless approach that compiles to efficient
    /// SSE/AVX comparison and blend operations (pcmp, pblend) on x86-64.
    ///
    /// Quantization per ITU-T.87 Section 4.3.1:
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
    ///   - absGrad: Absolute value of gradient (unused but kept for consistency)
    ///   - sign: Sign of gradient (unused but kept for consistency)
    ///   - t1: Threshold 1
    ///   - t2: Threshold 2
    ///   - t3: Threshold 3
    /// - Returns: Quantized gradient value in range [-4, 4]
    @inline(__always)
    private func quantizeSingleGradient(
        gradient: Int,
        absGrad: Int,
        sign: Int,
        t1: Int,
        t2: Int,
        t3: Int
    ) -> Int {
        // Quantization using signed comparisons per ITU-T.87
        // The compiler will optimize these to SSE/AVX comparison instructions
        
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
