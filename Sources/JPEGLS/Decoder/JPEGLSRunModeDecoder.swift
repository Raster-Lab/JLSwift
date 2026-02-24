/// JPEG-LS run mode decoding implementation per ITU-T.87.
///
/// Run mode decoding reverses the encoding process:
/// 1. Decode run length from bitstream using J[RUNindex] mapping
/// 2. Reconstruct run of identical pixel values
/// 3. Decode run interruption sample when run terminates
/// 4. Update context statistics for adaptation

import Foundation

/// Run mode decoder for JPEG-LS decompression.
///
/// The run mode decoder implements the inverse of the encoding algorithm:
/// 1. Detect if we should enter run mode (Ra == Rb)
/// 2. Decode run length from continuation bits and remainder
/// 3. Reconstruct the run of identical pixels using the run value (Ra)
/// 4. When run is interrupted, decode the interruption sample
/// 5. Update run index for adaptation
public struct JPEGLSRunModeDecoder: Sendable {
    // MARK: - Properties
    
    /// Preset parameters controlling thresholds and limits
    private let parameters: JPEGLSPresetParameters
    
    /// Near-lossless parameter (0 for lossless mode)
    private let near: Int
    
    /// Maximum run length that can be decoded in one iteration
    private let maxRunLength: Int
    
    // MARK: - Initialization
    
    /// Initialize run mode decoder with preset parameters.
    ///
    /// - Parameters:
    ///   - parameters: Preset parameters (thresholds, MAXVAL, RESET)
    ///   - near: Near-lossless parameter (0 for lossless mode)
    ///   - maxRunLength: Maximum run length to decode (default: 65536)
    /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is invalid
    public init(
        parameters: JPEGLSPresetParameters,
        near: Int = 0,
        maxRunLength: Int = 65536
    ) throws {
        guard near >= 0 && near <= 255 else {
            throw JPEGLSError.invalidNearParameter(near: near)
        }
        
        self.parameters = parameters
        self.near = near
        self.maxRunLength = maxRunLength
    }
    
    // MARK: - Run Detection
    
    /// Check if run mode should be entered.
    ///
    /// Per ITU-T.87 Section 4.5.1, run mode is entered when:
    /// - Ra == Rb (left and top neighbors are equal)
    ///
    /// This indicates a potentially flat region where run-length decoding
    /// should be used.
    ///
    /// - Parameters:
    ///   - a: Left neighbor pixel value (Ra)
    ///   - b: Top neighbor pixel value (Rb)
    /// - Returns: True if run mode should be entered
    public func shouldEnterRunMode(a: Int, b: Int) -> Bool {
        return a == b
    }
    
    // MARK: - J[RUNindex] Mapping
    
    /// Standard J table per ITU-T.87 Annex J (Table J.1)
    private static let jTable: [Int] = [
        0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
        4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15
    ]
    
    /// Compute the number of bits for encoding/decoding a run length.
    ///
    /// Per ITU-T.87 Annex J, J[RUNindex] determines the run length
    /// block size as 2^J[RUNindex].
    ///
    /// - Parameter runIndex: Current run index (0 to 31)
    /// - Returns: Number of bits for run length encoding (J value)
    public func computeJ(runIndex: Int) -> Int {
        let idx = max(0, min(runIndex, Self.jTable.count - 1))
        return Self.jTable[idx]
    }
    
    // MARK: - Run-Length Decoding
    
    /// Decode a run length from continuation bits and remainder.
    ///
    /// Per ITU-T.87 Section 4.5, run decoding reverses the encoding:
    /// 1. Each '1' bit represents a full block of 2^J pixels
    /// 2. A '0' bit indicates termination
    /// 3. Following J bits contain the remainder
    ///
    /// This method reconstructs the total run length from the decoded values.
    ///
    /// - Parameters:
    ///   - continuationBits: Number of '1' continuation bits (each = 2^J pixels)
    ///   - remainder: Remainder value decoded from J bits
    ///   - runIndex: Current run index (determines J value)
    /// - Returns: Decoded run result with total run length
    public func decodeRunLength(
        continuationBits: Int,
        remainder: Int,
        runIndex: Int
    ) -> DecodedRun {
        let j = computeJ(runIndex: runIndex)
        let blockSize = 1 << j  // 2^J
        
        // Total run length = (continuation blocks × block size) + remainder
        let totalRunLength = continuationBits * blockSize + remainder
        
        return DecodedRun(
            runIndex: runIndex,
            j: j,
            continuationBits: continuationBits,
            remainder: remainder,
            totalRunLength: totalRunLength
        )
    }
    
    /// Decode run length directly from raw bit values.
    ///
    /// This is an alternative interface that takes the raw continuation count
    /// and remainder bits as read from the bitstream.
    ///
    /// - Parameters:
    ///   - continuationCount: Number of '1' bits before the '0' terminator
    ///   - remainderBits: J-bit remainder value after the terminator
    ///   - runIndex: Current run index
    /// - Returns: Total decoded run length
    public func decodeRunLengthDirect(
        continuationCount: Int,
        remainderBits: Int,
        runIndex: Int
    ) -> Int {
        let j = computeJ(runIndex: runIndex)
        let blockSize = 1 << j
        return continuationCount * blockSize + remainderBits
    }
    
    // MARK: - Run Interruption Decoding
    
    /// Decode a run interruption sample per ITU-T.87 §A.7.
    ///
    /// When a run is interrupted, the differing pixel is encoded using a
    /// prediction based on Ra (run value) and Rb (top pixel at the interruption
    /// position). The prediction and sign depend on which is larger:
    /// - If Ra ≥ Rb: Pred = Ra, Isign = +1
    /// - If Ra < Rb: Pred = Rb, Isign = -1
    ///
    /// RItype (0 = Ra≠Rb, 1 = Ra==Rb) determines an additional ±1 correction
    /// applied by the encoder to avoid redundant zero-coding in lossless mode.
    ///
    /// - Parameters:
    ///   - mappedError: Non-negative mapped error (MErrval) from bitstream
    ///   - runValue: Ra — the value of the run (left neighbour at run start)
    ///   - topValue: Rb — the top (above) neighbour at the interruption position
    /// - Returns: Decoded run interruption result with sample value
    public func decodeRunInterruption(
        mappedError: Int,
        runValue: Int,
        topValue: Int
    ) -> DecodedRunInterruption {
        // Determine RItype and prediction per ITU-T.87 §A.7
        let riType = (abs(runValue - topValue) <= near) ? 1 : 0
        let prediction: Int
        let sign: Int
        if runValue >= topValue {
            prediction = runValue
            sign = 1
        } else {
            prediction = topValue
            sign = -1
        }
        
        // Unmap MErrval to signed Errval
        var errval: Int
        if mappedError % 2 == 0 {
            errval = mappedError / 2
        } else {
            errval = -((mappedError + 1) / 2)
        }
        
        // Reverse the RItype==0 encoder adjustment (encoder decremented Errval by 1 mod RANGE)
        if riType == 0 {
            errval += 1
            let range = parameters.maxValue + 1
            if errval > (range - 1) / 2 {
                errval -= range
            }
        }
        
        // Reconstruct sample: Tpred + Isign × Errval
        var sample = prediction + sign * errval
        
        // Modular reduction
        let range = parameters.maxValue + 1
        if sample < 0 {
            sample += range
        } else if sample > parameters.maxValue {
            sample -= range
        }
        
        // Clamp to valid range [0, MAXVAL]
        sample = max(0, min(parameters.maxValue, sample))
        
        return DecodedRunInterruption(
            prediction: prediction,
            mappedError: mappedError,
            error: errval,
            sample: sample
        )
    }
    
    /// Unmap a non-negative error back to signed error.
    ///
    /// Per ITU-T.87 Section 4.4.1, this reverses the mapping:
    /// - If MErrval is even: Errval = MErrval / 2
    /// - If MErrval is odd: Errval = -(MErrval + 1) / 2
    ///
    /// - Parameter mappedError: Non-negative mapped error (MErrval)
    /// - Returns: Signed prediction error
    public func unmapError(_ mappedError: Int) -> Int {
        if mappedError % 2 == 0 {
            // Even: positive error
            return mappedError / 2
        } else {
            // Odd: negative error
            return -((mappedError + 1) / 2)
        }
    }
    
    /// Decode run interruption from Golomb-Rice encoded bitstream values.
    ///
    /// This method takes the raw Golomb-Rice decoded value and
    /// computes the interruption sample.
    ///
    /// - Parameters:
    ///   - unaryCount: Number of zeros in unary prefix (quotient)
    ///   - remainder: Binary remainder (k bits)
    ///   - k: Golomb-Rice parameter
    ///   - runValue: Ra — the value of the run (left neighbour at run start)
    ///   - topValue: Rb — the top neighbour at the interruption position
    /// - Returns: Decoded run interruption result
    public func decodeRunInterruptionFromBits(
        unaryCount: Int,
        remainder: Int,
        k: Int,
        runValue: Int,
        topValue: Int
    ) -> DecodedRunInterruption {
        // Reconstruct mapped error from Golomb-Rice encoding
        let mappedError = (unaryCount << k) | remainder
        
        return decodeRunInterruption(mappedError: mappedError, runValue: runValue, topValue: topValue)
    }
    
    // MARK: - Context Adaptation
    
    /// Update run index based on completed run length.
    ///
    /// Per ITU-T.87 Section 4.5.3, the run index adapts based on:
    /// - Longer runs → increase RUNindex (up to maximum of 31)
    /// - Shorter runs → decrease RUNindex (down to minimum of 0)
    ///
    /// This is identical to the encoder adaptation to maintain sync.
    ///
    /// - Parameters:
    ///   - currentRunIndex: Current run index before adaptation
    ///   - completedRunLength: Length of the just-decoded run
    /// - Returns: Updated run index
    public func adaptRunIndex(
        currentRunIndex: Int,
        completedRunLength: Int
    ) -> Int {
        // Already at maximum, can't increase
        if currentRunIndex >= 31 {
            return 31
        }
        
        // Already at minimum, can't decrease
        if currentRunIndex <= 0 {
            return 0
        }
        
        let j = computeJ(runIndex: currentRunIndex)
        let blockSize = 1 << j  // 2^J
        
        var newRunIndex = currentRunIndex
        
        // Increase index if run was long
        if completedRunLength > blockSize {
            newRunIndex = min(currentRunIndex + 1, 31)
        }
        // Decrease index if run was short
        else if j > 0 && completedRunLength < (1 << (j - 1)) {
            newRunIndex = max(currentRunIndex - 1, 0)
        }
        
        return newRunIndex
    }
    
    // MARK: - Run Pixel Reconstruction
    
    /// Reconstruct run pixels from decoded run length.
    ///
    /// Given a run value and length, generates the array of pixels
    /// representing the run.
    ///
    /// - Parameters:
    ///   - runValue: The pixel value for the run
    ///   - runLength: Number of pixels in the run
    /// - Returns: Array of pixel values (all equal to runValue)
    public func reconstructRunPixels(runValue: Int, runLength: Int) -> [Int] {
        return Array(repeating: runValue, count: runLength)
    }
    
    // MARK: - Golomb-Rice Decoding
    
    /// Decode a Golomb-Rice encoded value.
    ///
    /// Per ITU-T.87 Section 4.4, Golomb-Rice decoding:
    /// - Read unary code (count zeros until a 1)
    /// - Read k bits for the remainder
    /// - Reconstruct value: (quotient << k) | remainder
    ///
    /// - Parameters:
    ///   - unaryCount: Number of zeros in unary prefix (quotient)
    ///   - remainder: Binary remainder (k bits)
    ///   - k: Golomb-Rice parameter
    /// - Returns: Decoded non-negative value (MErrval)
    public func golombDecode(unaryCount: Int, remainder: Int, k: Int) -> Int {
        return (unaryCount << k) | remainder
    }
    
    // MARK: - Complete Run Mode Decoding Pipeline
    
    /// Decode a complete run from bitstream-style input.
    ///
    /// This method combines all steps of run mode decoding:
    /// 1. Decode run length from continuation and remainder
    /// 2. Optionally decode run interruption sample
    ///
    /// - Parameters:
    ///   - continuationBits: Number of '1' bits representing full blocks
    ///   - remainder: Remainder bits
    ///   - runIndex: Current run index
    ///   - runValue: Ra — the pixel value for the run
    ///   - topValue: Rb — the top neighbour at the interruption position
    ///   - isRunTerminated: Whether the run was interrupted (not at end of line)
    ///   - interruptionMappedError: Mapped error for interruption sample (if terminated)
    /// - Returns: Complete decoded run result
    public func decodeCompleteRun(
        continuationBits: Int,
        remainder: Int,
        runIndex: Int,
        runValue: Int,
        topValue: Int,
        isRunTerminated: Bool,
        interruptionMappedError: Int?
    ) -> CompleteDecodedRun {
        // Decode run length
        let decodedRun = decodeRunLength(
            continuationBits: continuationBits,
            remainder: remainder,
            runIndex: runIndex
        )
        
        // Generate run pixels
        let runPixels = reconstructRunPixels(
            runValue: runValue,
            runLength: decodedRun.totalRunLength
        )
        
        // Decode interruption sample if present
        var interruptionSample: Int?
        var decodedInterruption: DecodedRunInterruption?
        
        if isRunTerminated, let mappedError = interruptionMappedError {
            let interruption = decodeRunInterruption(
                mappedError: mappedError,
                runValue: runValue,
                topValue: topValue
            )
            interruptionSample = interruption.sample
            decodedInterruption = interruption
        }
        
        // Compute adapted run index
        let adaptedRunIndex = adaptRunIndex(
            currentRunIndex: runIndex,
            completedRunLength: decodedRun.totalRunLength
        )
        
        return CompleteDecodedRun(
            runLength: decodedRun.totalRunLength,
            runValue: runValue,
            runPixels: runPixels,
            interruptionSample: interruptionSample,
            decodedInterruption: decodedInterruption,
            adaptedRunIndex: adaptedRunIndex
        )
    }
    
    // MARK: - Run Limit Checking
    
    /// Check if run length is within valid bounds.
    ///
    /// - Parameter runLength: Decoded run length
    /// - Returns: True if run length is valid
    public func isValidRunLength(_ runLength: Int) -> Bool {
        return runLength >= 0 && runLength <= maxRunLength
    }
}

// MARK: - Decoded Run Result

/// Result of decoding a run of identical pixels.
///
/// Contains the decoded values and metadata from run decoding.
public struct DecodedRun: Sendable, Equatable {
    /// Run index used for decoding (determines J value)
    public let runIndex: Int
    
    /// J value (number of bits for remainder)
    public let j: Int
    
    /// Number of continuation bits decoded
    public let continuationBits: Int
    
    /// Remainder value decoded from J bits
    public let remainder: Int
    
    /// Total decoded run length
    public let totalRunLength: Int
    
    /// Initialize a decoded run result.
    ///
    /// - Parameters:
    ///   - runIndex: Run index used for decoding
    ///   - j: J value (bits for remainder)
    ///   - continuationBits: Number of continuation bits
    ///   - remainder: Remainder value
    ///   - totalRunLength: Total decoded run length
    public init(
        runIndex: Int,
        j: Int,
        continuationBits: Int,
        remainder: Int,
        totalRunLength: Int
    ) {
        self.runIndex = runIndex
        self.j = j
        self.continuationBits = continuationBits
        self.remainder = remainder
        self.totalRunLength = totalRunLength
    }
}

// MARK: - Decoded Run Interruption Result

/// Result of decoding a run interruption sample.
///
/// When a run is interrupted, the differing pixel is decoded with
/// its prediction error.
public struct DecodedRunInterruption: Sendable, Equatable {
    /// Predicted value (the run value)
    public let prediction: Int
    
    /// Mapped non-negative error (MErrval) from bitstream
    public let mappedError: Int
    
    /// Signed prediction error
    public let error: Int
    
    /// Reconstructed sample value
    public let sample: Int
    
    /// Initialize a decoded run interruption result.
    ///
    /// - Parameters:
    ///   - prediction: Predicted value (run value)
    ///   - mappedError: Mapped non-negative error
    ///   - error: Signed prediction error
    ///   - sample: Reconstructed sample value
    public init(
        prediction: Int,
        mappedError: Int,
        error: Int,
        sample: Int
    ) {
        self.prediction = prediction
        self.mappedError = mappedError
        self.error = error
        self.sample = sample
    }
}

// MARK: - Complete Decoded Run Result

/// Complete result of decoding a run with optional interruption.
///
/// Contains the run pixels, optional interruption sample, and
/// adapted run index for the next iteration.
public struct CompleteDecodedRun: Sendable, Equatable {
    /// Length of the decoded run
    public let runLength: Int
    
    /// Pixel value of the run
    public let runValue: Int
    
    /// Array of run pixel values
    public let runPixels: [Int]
    
    /// Interruption sample value (nil if run ended at line end)
    public let interruptionSample: Int?
    
    /// Full decoded interruption result (nil if no interruption)
    public let decodedInterruption: DecodedRunInterruption?
    
    /// Adapted run index for next iteration
    public let adaptedRunIndex: Int
    
    /// Total number of pixels decoded (run + optional interruption)
    public var totalPixels: Int {
        return runLength + (interruptionSample != nil ? 1 : 0)
    }
    
    /// Initialize a complete decoded run result.
    ///
    /// - Parameters:
    ///   - runLength: Length of the decoded run
    ///   - runValue: Pixel value of the run
    ///   - runPixels: Array of run pixel values
    ///   - interruptionSample: Interruption sample value (optional)
    ///   - decodedInterruption: Full decoded interruption (optional)
    ///   - adaptedRunIndex: Adapted run index
    public init(
        runLength: Int,
        runValue: Int,
        runPixels: [Int],
        interruptionSample: Int?,
        decodedInterruption: DecodedRunInterruption?,
        adaptedRunIndex: Int
    ) {
        self.runLength = runLength
        self.runValue = runValue
        self.runPixels = runPixels
        self.interruptionSample = interruptionSample
        self.decodedInterruption = decodedInterruption
        self.adaptedRunIndex = adaptedRunIndex
    }
}
