/// JPEG-LS regular mode encoding implementation per ITU-T.87.
///
/// Regular mode is the primary encoding mode for JPEG-LS, used when the local
/// gradient indicates non-uniform pixel values. It uses context-based adaptive
/// prediction and Golomb-Rice coding to compress prediction errors efficiently.

import Foundation

/// Regular mode encoder for JPEG-LS compression.
///
/// The regular mode encoder implements the core JPEG-LS algorithm:
/// 1. Compute local gradients (D1, D2, D3) around the current pixel
/// 2. Quantize gradients to determine context
/// 3. Predict pixel value using MED (Median Edge Detector)
/// 4. Apply bias correction based on context statistics
/// 5. Compute prediction error with modular reduction
/// 6. Encode error using Golomb-Rice coding
/// 7. Update context statistics for adaptation
public struct JPEGLSRegularMode: Sendable {
    // MARK: - Properties
    
    /// Preset parameters controlling thresholds and limits
    private let parameters: JPEGLSPresetParameters
    
    /// Near-lossless parameter (0 for lossless mode)
    private let near: Int
    
    /// Range value: RANGE = (MAXVAL + 2*NEAR)/qbpp + 1
    /// Used for modular reduction of prediction errors
    private let range: Int
    
    /// Quantization factor: qbpp = (NEAR == 0) ? 0 : ((NEAR << 1) | 1)
    private let qbpp: Int
    
    // MARK: - Initialization
    
    /// Initialize regular mode encoder with preset parameters.
    ///
    /// - Parameters:
    ///   - parameters: Preset parameters (thresholds, MAXVAL, RESET)
    ///   - near: Near-lossless parameter (0 for lossless mode)
    /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is invalid
    public init(parameters: JPEGLSPresetParameters, near: Int = 0) throws {
        guard near >= 0 && near <= 255 else {
            throw JPEGLSError.invalidNearParameter(near: near)
        }
        
        self.parameters = parameters
        self.near = near
        
        // Compute quantization factor per ITU-T.87 Section 4.2.1
        self.qbpp = (near == 0) ? 0 : ((near << 1) | 1)
        
        // Compute RANGE per ITU-T.87 Section 4.2.1
        // RANGE = (MAXVAL + 2*NEAR)/qbpp + 1
        if near == 0 {
            self.range = parameters.maxValue + 1
        } else {
            self.range = (parameters.maxValue + 2 * near) / qbpp + 1
        }
    }
    
    // MARK: - Gradient Computation
    
    /// Compute local gradients for regular mode detection.
    ///
    /// Per ITU-T.87 Section 4.1.1, three gradients are computed:
    /// - D1 = d - b  (top-right minus top)
    /// - D2 = b - c  (top minus top-left)
    /// - D3 = c - a  (top-left minus left)
    ///
    /// where the pixel arrangement is:
    /// ```
    ///   c b d
    ///   a x  (x is current pixel being encoded)
    /// ```
    ///
    /// - Parameters:
    ///   - a: Left neighbor pixel value
    ///   - b: Top neighbor pixel value
    ///   - c: Top-left diagonal neighbor pixel value
    ///   - d: Top-right diagonal neighbor pixel value
    /// - Returns: Tuple of (D1, D2, D3) gradients
    public func computeGradients(a: Int, b: Int, c: Int, d: Int) -> (d1: Int, d2: Int, d3: Int) {
        let d1 = d - b  // Top-right minus top
        let d2 = b - c  // Top minus top-left
        let d3 = c - a  // Top-left minus left
        
        return (d1, d2, d3)
    }
    
    /// Quantize a gradient value into the range [-4, 4].
    ///
    /// Per ITU-T.87 Section 4.3.1, gradients are quantized using the
    /// threshold parameters T1, T2, T3 to produce quantization indices
    /// in the range [-4, 4].
    ///
    /// - Parameter gradient: Raw gradient value
    /// - Returns: Quantized gradient in range [-4, 4]
    public func quantizeGradient(_ gradient: Int) -> Int {
        let absGrad = abs(gradient)
        let sign = gradient >= 0 ? 1 : -1
        
        // Quantization per ITU-T.87 Section 4.3.1:
        // Q = 0 if |d| <= NEAR
        // Q = sign(d) × 1 if NEAR < |d| <= T1
        // Q = sign(d) × 2 if T1 < |d| <= T2
        // Q = sign(d) × 3 if T2 < |d| <= T3
        // Q = sign(d) × 4 if T3 < |d|
        
        if absGrad <= near {
            return 0
        } else if absGrad <= parameters.threshold1 {
            return sign * 1
        } else if absGrad <= parameters.threshold2 {
            return sign * 2
        } else if absGrad <= parameters.threshold3 {
            return sign * 3
        } else {
            return sign * 4
        }
    }
    
    // MARK: - MED Prediction
    
    /// Compute MED (Median Edge Detector) prediction.
    ///
    /// Per ITU-T.87 Section 4.1.1, the MED predictor selects between
    /// three neighbor pixels based on their gradient pattern:
    ///
    /// ```
    ///   c b
    ///   a x  (x is current pixel being predicted)
    /// ```
    ///
    /// The prediction logic:
    /// - If c >= max(a, b): Px = min(a, b)
    /// - If c <= min(a, b): Px = max(a, b)
    /// - Otherwise: Px = a + b - c
    ///
    /// - Parameters:
    ///   - a: Left neighbor pixel value
    ///   - b: Top neighbor pixel value
    ///   - c: Top-left diagonal neighbor pixel value
    /// - Returns: Predicted pixel value
    public func computeMEDPrediction(a: Int, b: Int, c: Int) -> Int {
        // MED prediction per ITU-T.87 Section 4.1.1
        if c >= max(a, b) {
            return min(a, b)
        } else if c <= min(a, b) {
            return max(a, b)
        } else {
            return a + b - c
        }
    }
    
    // MARK: - Bias Correction
    
    /// Apply bias correction to prediction.
    ///
    /// Per ITU-T.87 Section 4.3.3, bias correction adjusts the prediction
    /// based on accumulated context statistics to reduce systematic errors.
    ///
    /// - Parameters:
    ///   - prediction: Base prediction value (from MED)
    ///   - biasC: Bias correction value from context (C array)
    ///   - sign: Context sign (+1 or -1)
    /// - Returns: Bias-corrected prediction
    public func applyBiasCorrection(prediction: Int, biasC: Int, sign: Int) -> Int {
        // Bias correction per ITU-T.87 Section 4.3.3
        // Corrected prediction = Px + sign × C[context]
        let corrected = prediction + sign * biasC
        
        // Clamp to valid range [0, MAXVAL]
        return max(0, min(parameters.maxValue, corrected))
    }
    
    // MARK: - Prediction Error
    
    /// Compute prediction error with modular reduction.
    ///
    /// Per ITU-T.87 Section 4.2.2, the prediction error is computed as:
    /// - Errval = x - Px' (x is actual value, Px' is corrected prediction)
    ///
    /// For modular reduction (near-lossless mode):
    /// - Errval is reduced modulo RANGE to ensure it falls in [-RANGE/2, RANGE/2)
    ///
    /// - Parameters:
    ///   - actual: Actual pixel value
    ///   - prediction: Corrected prediction value
    /// - Returns: Prediction error with modular reduction applied
    public func computePredictionError(actual: Int, prediction: Int) -> Int {
        var error = actual - prediction
        
        // Apply modular reduction per ITU-T.87 Section 4.2.2
        // This ensures error is in the range [-(RANGE-1)/2, (RANGE-1)/2]
        if error > (range - 1) / 2 {
            error -= range
        } else if error < -(range / 2) {
            error += range
        }
        
        return error
    }
    
    /// Map prediction error to non-negative value for Golomb coding.
    ///
    /// Per ITU-T.87 Section 4.4.1, the signed prediction error is mapped
    /// to a non-negative MErrval for Golomb-Rice encoding:
    /// - If Errval >= 0: MErrval = 2 × Errval
    /// - If Errval < 0: MErrval = -2 × Errval - 1
    ///
    /// - Parameter error: Signed prediction error
    /// - Returns: Mapped non-negative error value
    public func mapErrorToNonNegative(_ error: Int) -> Int {
        if error >= 0 {
            return 2 * error
        } else {
            return -2 * error - 1
        }
    }
    
    // MARK: - Golomb-Rice Encoding
    
    /// Encode a value using Golomb-Rice coding.
    ///
    /// Per ITU-T.87 Section 4.4, Golomb-Rice coding encodes a non-negative
    /// integer n with parameter k as:
    /// - Quotient: q = n >> k (encoded in unary: q zeros followed by a 1)
    /// - Remainder: r = n & ((1 << k) - 1) (encoded in binary using k bits)
    ///
    /// - Parameters:
    ///   - value: Non-negative value to encode (MErrval)
    ///   - k: Golomb-Rice parameter (from context)
    /// - Returns: Tuple of (unaryLength, remainder) for bitstream writing
    public func golombEncode(value: Int, k: Int) -> (unaryLength: Int, remainder: Int) {
        // Golomb-Rice encoding per ITU-T.87 Section 4.4
        let quotient = value >> k
        let remainder = value & ((1 << k) - 1)
        
        // Unary prefix length is the number of zeros (quotient)
        // The terminating 1-bit is written separately by the bitstream writer
        let unaryLength = quotient
        
        return (unaryLength, remainder)
    }
    
    /// Compute total bit length for Golomb-Rice encoded value.
    ///
    /// - Parameters:
    ///   - value: Non-negative value to encode
    ///   - k: Golomb-Rice parameter
    /// - Returns: Total number of bits required
    public func golombBitLength(value: Int, k: Int) -> Int {
        let quotient = value >> k
        // Total bits = unary length + k bits for remainder
        return quotient + 1 + k
    }
    
    // MARK: - Complete Encoding Pipeline
    
    /// Encode a single pixel in regular mode.
    ///
    /// This is the complete encoding pipeline combining all steps:
    /// 1. Compute gradients
    /// 2. Quantize gradients
    /// 3. Compute context index
    /// 4. Compute MED prediction
    /// 5. Apply bias correction
    /// 6. Compute prediction error
    /// 7. Map to non-negative
    /// 8. Determine Golomb parameter k
    /// 9. Encode using Golomb-Rice
    ///
    /// - Parameters:
    ///   - actual: Actual pixel value to encode
    ///   - a: Left neighbor pixel value
    ///   - b: Top neighbor pixel value
    ///   - c: Top-left diagonal neighbor pixel value
    ///   - context: Context model (for accessing statistics)
    /// - Returns: Encoded result with context info and encoded bits
    public func encodePixel(
        actual: Int,
        a: Int,
        b: Int,
        c: Int,
        d: Int,
        context: JPEGLSContextModel
    ) -> EncodedPixel {
        // Step 1: Compute local gradients
        let (d1, d2, d3) = computeGradients(a: a, b: b, c: c, d: d)
        
        // Step 2: Quantize gradients
        let q1 = quantizeGradient(d1)
        let q2 = quantizeGradient(d2)
        let q3 = quantizeGradient(d3)
        
        // Step 3: Compute context index and sign
        let contextIndex = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
        let sign = context.computeContextSign(q1: q1, q2: q2, q3: q3)
        
        // Step 4: Compute MED prediction
        let basePrediction = computeMEDPrediction(a: a, b: b, c: c)
        
        // Step 5: Apply bias correction
        let biasC = context.getC(contextIndex: contextIndex)
        let correctedPrediction = applyBiasCorrection(
            prediction: basePrediction,
            biasC: biasC,
            sign: sign
        )
        
        // Step 6: Compute prediction error with modular reduction
        let error = computePredictionError(actual: actual, prediction: correctedPrediction)
        
        // Step 7: Map to non-negative for Golomb coding
        let mappedError = mapErrorToNonNegative(error)
        
        // Step 8: Get Golomb parameter k from context
        let k = context.computeGolombParameter(contextIndex: contextIndex)
        
        // Step 9: Encode using Golomb-Rice
        let (unaryLength, remainder) = golombEncode(value: mappedError, k: k)
        
        return EncodedPixel(
            contextIndex: contextIndex,
            sign: sign,
            prediction: correctedPrediction,
            error: error,
            mappedError: mappedError,
            golombK: k,
            unaryLength: unaryLength,
            remainder: remainder
        )
    }
}

// MARK: - Encoded Pixel Result

/// Result of encoding a single pixel in regular mode.
///
/// Contains all intermediate values and final encoded bits for testing
/// and bitstream writing.
public struct EncodedPixel: Sendable {
    /// Context index used (0 to 364)
    public let contextIndex: Int
    
    /// Context sign (+1 or -1)
    public let sign: Int
    
    /// Bias-corrected prediction value
    public let prediction: Int
    
    /// Signed prediction error
    public let error: Int
    
    /// Mapped non-negative error (MErrval)
    public let mappedError: Int
    
    /// Golomb-Rice parameter k
    public let golombK: Int
    
    /// Unary code length (quotient + 1)
    public let unaryLength: Int
    
    /// Binary remainder (k bits)
    public let remainder: Int
    
    /// Total encoded bit length
    public var totalBitLength: Int {
        return unaryLength + 1 + golombK
    }
}
