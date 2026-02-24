/// JPEG-LS preset coding parameters per ITU-T.87
///
/// These parameters control the encoding/decoding behavior and can be customized
/// via the JPEG-LS Extension (LSE) marker for optimal compression or compatibility.

import Foundation

/// Preset coding parameters for JPEG-LS
///
/// The JPEG-LS standard defines default parameters that work well for most images,
/// but allows customization through preset parameters for specific use cases.
public struct JPEGLSPresetParameters: Sendable, Equatable {
    /// Maximum sample value (default: 2^bitsPerSample - 1)
    public let maxValue: Int
    
    /// Threshold 1 for gradient quantization (default: computed from MAXVAL)
    public let threshold1: Int
    
    /// Threshold 2 for gradient quantization (default: computed from MAXVAL)
    public let threshold2: Int
    
    /// Threshold 3 for gradient quantization (default: computed from MAXVAL)
    public let threshold3: Int
    
    /// Reset value for context counters (default: 64)
    public let reset: Int
    
    /// Initialize with custom parameters
    ///
    /// - Parameters:
    ///   - maxValue: Maximum sample value (MAXVAL)
    ///   - threshold1: Gradient quantization threshold T1
    ///   - threshold2: Gradient quantization threshold T2
    ///   - threshold3: Gradient quantization threshold T3
    ///   - reset: Context counter reset value
    /// - Throws: `JPEGLSError.invalidPresetParameters` if parameters are invalid
    public init(
        maxValue: Int,
        threshold1: Int,
        threshold2: Int,
        threshold3: Int,
        reset: Int
    ) throws {
        // Validate parameters according to ITU-T.87 Section 4.2
        guard maxValue >= 1 && maxValue <= 65535 else {
            throw JPEGLSError.invalidPresetParameters(
                reason: "MAXVAL must be in range [1, 65535], got \(maxValue)"
            )
        }
        
        guard threshold1 >= 1 && threshold1 <= maxValue else {
            throw JPEGLSError.invalidPresetParameters(
                reason: "T1 must be in range [1, MAXVAL], got \(threshold1)"
            )
        }
        
        guard threshold2 >= threshold1 && threshold2 <= maxValue else {
            throw JPEGLSError.invalidPresetParameters(
                reason: "T2 must be in range [T1, MAXVAL], got \(threshold2)"
            )
        }
        
        guard threshold3 >= threshold2 && threshold3 <= maxValue else {
            throw JPEGLSError.invalidPresetParameters(
                reason: "T3 must be in range [T2, MAXVAL], got \(threshold3)"
            )
        }
        
        guard reset >= 3 && reset <= 255 else {
            throw JPEGLSError.invalidPresetParameters(
                reason: "RESET must be in range [3, 255], got \(reset)"
            )
        }
        
        self.maxValue = maxValue
        self.threshold1 = threshold1
        self.threshold2 = threshold2
        self.threshold3 = threshold3
        self.reset = reset
    }
    
    /// Compute default preset parameters for given bits per sample
    ///
    /// These defaults are defined in ITU-T.87 Section 4.2 and provide good
    /// compression performance for most natural images.
    ///
    /// - Parameter bitsPerSample: Number of bits per sample (2-16)
    /// - Returns: Default preset parameters
    /// - Throws: `JPEGLSError.invalidBitsPerSample` if bits per sample is invalid
    public static func defaultParameters(bitsPerSample: Int) throws -> JPEGLSPresetParameters {
        guard bitsPerSample >= 2 && bitsPerSample <= 16 else {
            throw JPEGLSError.invalidBitsPerSample(bits: bitsPerSample)
        }
        
        let maxValue = (1 << bitsPerSample) - 1
        
        // Default threshold calculations per ITU-T.87 §A.3.4 / Table D.2.
        // FACTOR = floor((min(MAXVAL, 4095) + 128) / 256)
        // T1 = FACTOR + 2, T2 = 4*FACTOR + 3, T3 = 17*FACTOR + 4
        // Verified against Table D.1: 8-bit → (3,7,21), 12-bit → (18,67,276).
        let scaleFactor = (min(maxValue, 4095) + 128) / 256  // integer floor division
        var threshold1 = max(2, scaleFactor + 2)
        var threshold2 = max(threshold1, 4 * scaleFactor + 3)
        var threshold3 = max(threshold2, 17 * scaleFactor + 4)
        
        // Ensure thresholds are within valid range and properly ordered
        threshold1 = min(threshold1, maxValue)
        threshold2 = min(max(threshold2, threshold1), maxValue)
        threshold3 = min(max(threshold3, threshold2), maxValue)
        
        // Default reset value
        let reset = 64
        
        return try JPEGLSPresetParameters(
            maxValue: maxValue,
            threshold1: threshold1,
            threshold2: threshold2,
            threshold3: threshold3,
            reset: reset
        )
    }
    
    /// Returns true if these are the default parameters for the given bits per sample
    public func isDefault(forBitsPerSample bitsPerSample: Int) -> Bool {
        guard let defaultParams = try? Self.defaultParameters(bitsPerSample: bitsPerSample) else {
            return false
        }
        return self == defaultParams
    }
}

extension JPEGLSPresetParameters: CustomStringConvertible {
    /// Human-readable summary of preset parameters
    public var description: String {
        return "JPEGLSPresetParameters(MAXVAL=\(maxValue), T1=\(threshold1), T2=\(threshold2), T3=\(threshold3), RESET=\(reset))"
    }
}
