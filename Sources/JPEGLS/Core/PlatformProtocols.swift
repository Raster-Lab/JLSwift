/// Platform abstraction protocols for JPEG-LS implementation.
///
/// These protocols define the interface for platform-specific optimizations,
/// allowing the JPEG-LS codec to leverage hardware acceleration on different
/// architectures while maintaining a clean separation of concerns.

import Foundation

// MARK: - Platform Accelerator Protocol

/// Protocol defining platform-specific acceleration capabilities.
///
/// Implementations of this protocol provide optimized routines for
/// JPEG-LS operations on specific hardware architectures (e.g., ARM64, x86-64).
public protocol PlatformAccelerator: Sendable {
    /// The name of the platform (e.g., "ARM64", "x86-64")
    static var platformName: String { get }
    
    /// Returns true if this accelerator is supported on the current hardware.
    static var isSupported: Bool { get }
    
    /// Compute gradients for three neighboring pixels.
    ///
    /// Gradients are used in JPEG-LS for context determination and prediction.
    ///
    /// - Parameters:
    ///   - a: North pixel value
    ///   - b: West pixel value
    ///   - c: Northwest pixel value
    /// - Returns: A tuple of three gradients (D1, D2, D3)
    func computeGradients(a: Int, b: Int, c: Int) -> (d1: Int, d2: Int, d3: Int)
    
    /// Compute the Median Edge Detector (MED) prediction.
    ///
    /// The MED predictor is the core prediction algorithm in JPEG-LS.
    ///
    /// - Parameters:
    ///   - a: North pixel value
    ///   - b: West pixel value
    ///   - c: Northwest pixel value
    /// - Returns: The predicted pixel value
    func medPredictor(a: Int, b: Int, c: Int) -> Int
    
    /// Quantize gradients to context indices.
    ///
    /// Gradient quantization maps continuous gradient values to discrete
    /// context bins for context-adaptive coding.
    ///
    /// - Parameters:
    ///   - d1: First gradient
    ///   - d2: Second gradient
    ///   - d3: Third gradient
    ///   - t1: Quantization threshold 1
    ///   - t2: Quantization threshold 2
    ///   - t3: Quantization threshold 3
    /// - Returns: A tuple of three quantized gradient values (Q1, Q2, Q3)
    func quantizeGradients(d1: Int, d2: Int, d3: Int, t1: Int, t2: Int, t3: Int) -> (q1: Int, q2: Int, q3: Int)
}

// MARK: - Default Implementation

/// Default scalar implementation of platform acceleration.
///
/// This implementation provides reference algorithms without hardware-specific
/// optimizations. It serves as a fallback and reference for platform-specific
/// implementations.
public struct ScalarAccelerator: PlatformAccelerator {
    public static let platformName = "Scalar"
    public static let isSupported = true
    
    /// Initialize a scalar accelerator
    public init() {}
    
    /// Compute gradients for JPEG-LS context modeling
    ///
    /// Calculates the three gradients used in context determination:
    /// - d1 = b - c (horizontal gradient)
    /// - d2 = a - c (vertical gradient)  
    /// - d3 = c - a (diagonal gradient)
    ///
    /// - Parameters:
    ///   - a: Left pixel value
    ///   - b: Top pixel value
    ///   - c: Top-left pixel value
    /// - Returns: Tuple of three gradients (d1, d2, d3)
    public func computeGradients(a: Int, b: Int, c: Int) -> (d1: Int, d2: Int, d3: Int) {
        let d1 = b - c
        let d2 = a - c
        let d3 = c - a
        return (d1, d2, d3)
    }
    
    /// Compute MED (Median Edge Detector) prediction
    ///
    /// Implements the non-linear predictor used in JPEG-LS regular mode:
    /// - If c >= max(a, b): return min(a, b)
    /// - If c <= min(a, b): return max(a, b)
    /// - Otherwise: return a + b - c
    ///
    /// - Parameters:
    ///   - a: Left pixel value
    ///   - b: Top pixel value
    ///   - c: Top-left pixel value
    /// - Returns: Predicted pixel value
    public func medPredictor(a: Int, b: Int, c: Int) -> Int {
        // MED predictor: median of three values
        if c >= max(a, b) {
            return min(a, b)
        } else if c <= min(a, b) {
            return max(a, b)
        } else {
            return a + b - c
        }
    }
    
    /// Quantize gradients for context index computation
    ///
    /// Maps each gradient to a quantized value in range [-4, 4] using
    /// threshold parameters T1, T2, T3 per JPEG-LS standard.
    ///
    /// - Parameters:
    ///   - d1: First gradient (horizontal)
    ///   - d2: Second gradient (vertical)
    ///   - d3: Third gradient (diagonal)
    ///   - t1: Threshold 1 (smallest)
    ///   - t2: Threshold 2 (medium)
    ///   - t3: Threshold 3 (largest)
    /// - Returns: Tuple of three quantized gradients (q1, q2, q3)
    public func quantizeGradients(d1: Int, d2: Int, d3: Int, t1: Int, t2: Int, t3: Int) -> (q1: Int, q2: Int, q3: Int) {
        func quantize(_ d: Int, t1: Int, t2: Int, t3: Int) -> Int {
            if d <= -t3 {
                return -4
            } else if d <= -t2 {
                return -3
            } else if d <= -t1 {
                return -2
            } else if d < 0 {
                return -1
            } else if d == 0 {
                return 0
            } else if d < t1 {
                return 1
            } else if d < t2 {
                return 2
            } else if d < t3 {
                return 3
            } else {
                return 4
            }
        }
        
        return (quantize(d1, t1: t1, t2: t2, t3: t3),
                quantize(d2, t1: t1, t2: t2, t3: t3),
                quantize(d3, t1: t1, t2: t2, t3: t3))
    }
}

// MARK: - Platform Selection

/// Selects the optimal platform accelerator for the current hardware.
///
/// This function returns the most efficient accelerator implementation
/// available on the current system, preferring hardware-accelerated
/// implementations when available.
///
/// - Returns: An instance of the optimal platform accelerator
public func selectPlatformAccelerator() -> any PlatformAccelerator {
    #if arch(arm64)
    // Check if ARM64 NEON accelerator is available
    if ARM64Accelerator.isSupported {
        return ARM64Accelerator()
    }
    #elseif arch(x86_64)
    // Check if x86-64 SIMD accelerator is available
    if X86_64Accelerator.isSupported {
        return X86_64Accelerator()
    }
    #endif
    
    // Fallback to scalar implementation
    return ScalarAccelerator()
}
